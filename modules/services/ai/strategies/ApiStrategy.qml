import QtQuick

// Base interface / helper for all AI provider strategies.
// Subclasses override getEndpoint, getHeaders, and parse methods.
QtObject {
    id: root

    property bool supportsStreaming: true
    property bool supportsReasoning: false
    property bool supportsVision: true
    property string reasoningField: "" // e.g. "reasoning_content" for DeepSeek
    // Controls how the provider picks a tool. Subclasses set sensible
    // defaults for their provider ("auto" for OpenAI-compat, "any" for
    // Anthropic). Ai.qml may override this on a per-request basis to
    // force a tool call when nudging the model through a multi-step chain.
    property string defaultToolChoice: "auto"
    // Anthropic + Gemini don't support `parallel_tool_calls`. Subclasses
    // for those providers can override this to false.
    property bool supportsParallelToolCalls: true

    function getEndpoint(modelObj, apiKey) { return ""; }
    function getHeaders(apiKey) { return []; }

    // Resolve the final tool_choice value for a request. Subclasses
    // override this to map `"required"` onto their provider-native
    // equivalent (Anthropic uses `tool_choice: {type: "any"}` instead
    // of the OpenAI string `"required"`).
    function resolveToolChoice(toolChoice, toolName) {
        // Default: pass through OpenAI-compatible string values verbatim.
        if (toolChoice === "auto" || toolChoice === "none"
                || toolChoice === "required") {
            return toolChoice;
        }
        if (toolChoice && typeof toolChoice === "object"
                && toolChoice.type === "tool"
                && toolChoice.name) {
            return { type: "tool", name: toolChoice.name };
        }
        return root.defaultToolChoice;
    }

    // Build the request body for a non-streaming request.
    //
    // `options` is currently used by OpenAI-compatible strategies to
    // pass `toolChoice` (default = `root.defaultToolChoice`, e.g.
    // "auto"). Anthropic + Gemini ignore the field — they map their
    // own tool_choice format inside `resolveToolChoice` and that
    // path isn't exercised yet because they don't support the
    // "required" nudge pattern. QML doesn't support function
    // overloading so all subclasses override this 4-arg variant
    // directly; callers (Ai.qml.makeRequest) must always pass 4
    // arguments even when `options` is null.
    function getBody(messages, model, tools, options) { return {}; }
    function getStreamBody(messages, model, tools, options) {
        let body = getBody(messages, model, tools, options);
        body.stream = true;
        return body;
    }

    function parseResponse(response) { return { content: "" }; }

    // Override in subclasses. Returns: { content, done, error, reasoningContent, toolCallDelta, toolCallId }
    function parseStreamChunk(line) {
        return { content: "", done: true, error: null, reasoningContent: "", toolCallDelta: null, toolCallId: "" };
    }

    // ========================================================================
    // Shared helpers
    // ========================================================================

    // Format internal messages to OpenAI-compatible content parts AND
    // translate our internal tool-call/tool-result shape into the
    // provider's required fields.
    //
    // Internal shape:
    //   { role: "user"|"assistant"|"system", content: "..." }
    //   { role: "assistant", content: "...", functionCall: { name, args }, toolCallId: "..." }
    //   { role: "function", name: "<tool name>", content: "<result>", tool_call_id: "..." }
    //
    // OpenAI-compatible shape:
    //   { role: "user"|"assistant"|"system", content: "..." }
    //   { role: "assistant", content: "...", tool_calls: [{ id, type: "function", function: { name, arguments } }] }
    //   { role: "tool", tool_call_id: "...", content: "..." }     ← not "function"!
    //
    // The previous version silently dropped functionCall / tool_call_id,
    // so the provider never saw that the assistant wanted to call a
    // tool AND rejected the follow-up "function" message outright. The
    // result: every tool call ended with "No response received from
    // the API." even though the tool itself had run.
    function formatMessages(messages) {
        let formatted = [];
        for (let i = 0; i < messages.length; i++) {
            let msg = messages[i];
            // Translate our internal "function" role (tool result)
            // to OpenAI's "tool" role. Anything other than the
            // recognized roles falls through unchanged.
            let role = msg.role;
            if (role === "function") {
                role = "tool";
            }
            let out = { role: role };

            if (msg.attachments && msg.attachments.length > 0) {
                // User message with images — OpenAI content parts format.
                let contentParts = [{ type: "text", text: msg.content || "" }];
                for (let j = 0; j < msg.attachments.length; j++) {
                    let att = msg.attachments[j];
                    if (att.type === "image") {
                        contentParts.push({
                            type: "image_url",
                            image_url: {
                                url: "data:" + (att.mimeType || "image/png") + ";base64," + (att.base64 || "")
                            }
                        });
                    }
                }
                out.content = contentParts;
            } else {
                out.content = msg.content || "";
            }

            // Assistant message that wants to call a tool —
            // OpenAI requires a tool_calls array on the assistant
            // message, not a functionCall blob.
            if (role === "assistant" && msg.functionCall) {
                let tc = msg.functionCall;
                // Use the stored toolCallId, fall back to the id inside
                // the functionCall object, and only generate a random id
                // as last resort. Mismatched ids break tool-result
                // pairing and cause the model to return empty responses
                // on the next turn.
                let callId = msg.toolCallId || tc.tool_call_id || ("call_" + Math.random().toString(36).slice(2));
                out.tool_calls = [{
                    id: callId,
                    type: "function",
                    function: {
                        name: tc.name || "",
                        // OpenAI requires arguments to be a JSON STRING,
                        // not a JS object. Our internal args is already
                        // a plain object, so we serialise here.
                        arguments: typeof tc.args === "string"
                            ? tc.args
                            : JSON.stringify(tc.args || {})
                    }
                }];
                // When tool_calls is present and there is no preface
                // text, omit content entirely. Some providers/gateways
                // handle null content better than an empty string when
                // tool_calls are present.
                if (!msg.content || msg.content === "") {
                    out.content = null;
                }
            }

            // Tool result: OpenAI requires tool_call_id on a
            // "tool"-role message. Map it through.
            //
            // Also: skip the `name` field on tool messages. The
            // internal representation still carries `name` (for
            // back-compat with the old "function" role), but the
            // OpenAI spec for `role: tool` only accepts
            // `{tool_call_id, content}` — a stray `name` confuses
            // gateways with strict schema validation and was a
            // contributing factor in the agent-mode "empty response"
            // bug (the API would silently drop the tool result and
            // the model would refuse the next tool call).
            if (role === "tool") {
                if (msg.tool_call_id) {
                    out.tool_call_id = msg.tool_call_id;
                }
            } else if (msg.name) {
                out.name = msg.name;
            }

            // DeepSeek: the `reasoning_content` (chain-of-thought) in
            // the thinking mode must be passed back to the API in every
            // assistant message that had it. The internal model stores
            // it as `reasoningContent` (camelCase); the API expects
            // `reasoning_content` (snake_case).
            if (role === "assistant" && msg.reasoningContent) {
                out.reasoning_content = msg.reasoningContent;
            }

            formatted.push(out);
        }
        return formatted;
    }

    // Format internal tool definitions to OpenAI function-calling format.
    function formatTools(tools) {
        if (!tools || tools.length === 0) return [];
        return tools.map(t => ({
            type: "function",
            function: {
                name: t.name,
                description: t.description,
                parameters: t.parameters
            }
        }));
    }

    // Normalize an endpoint so it ends with /v1/chat/completions when needed.
    function normalizeChatEndpoint(base) {
        if (!base) base = "";
        if (base.endsWith("/chat/completions"))
            return base;
        if (base.endsWith("/v1"))
            return base + "/chat/completions";
        return base + "/v1/chat/completions";
    }
}
