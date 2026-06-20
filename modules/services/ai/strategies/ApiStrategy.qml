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
    // Most OpenAI-compatible providers accept `tool_choice: "required"`
    // to force a tool call, but several local / small model families
    // reject it (Gemma, Llama-3, Phi-3, Mistral) and return an empty
    // completion instead. Strategies can override `false` here for
    // families that don't honour the field, OR the per-model detection
    // in `modelFamilyOverrides()` returns `supportsToolChoiceRequired:
    // false` for those names automatically.
    property bool supportsToolChoiceRequired: true
    // The model emits reasoning_content as a separate field (DeepSeek
    // R1, OpenAI o1/o3/gpt-5). Distinct from `supportsReasoning`
    // because the latter only controls whether we surface the field to
    // the UI — this one gates whether the parser looks for it.
    property bool supportsReasoningField: false
    // The model emits `...` thinking inline (qwen3, gemma thinking
    // mode, deepseek-r1 distilled, qwq) — needs tag-stripping in
    // parseResponse / parseStreamChunk to extract the visible answer.
    property bool supportsInlineThinking: false

    // ── Model-family detection ───────────────────────────────────────
    //
    // Different model families have different quirks that don't fit
    // neatly into a single boolean property. The list below tags each
    // known family with the overrides we need to apply so the body
    // builder and parser can adapt per-call.
    //
    // Mirrors Odysseus's _THINKING_MODEL_PATTERNS / _restricts_temperature
    // pattern but kept in the QML strategy layer so it can be queried
    // from the response parser too.
    //
    // Detection order: longest prefix wins (so `qwen3:7b-instruct` is
    // matched as qwen3, not qwen). Patterns are lowercase substring
    // matches against the model name.
    readonly property var _modelFamilyHints: [
        // ── Reasoning / thinking-capable ──
        // These models emit  `<think>...</think>` blocks or a
        // `reasoning_content` field. Treating that as the visible
        // answer makes the chat look like the AI produced empty
        // responses, which is the gemma2 / qwen3 symptom the user
        // hit. Stripping the tag + surfacing the rest fixes it.
        { match: "deepseek-r1", supportsInlineThinking: true,
            supportsReasoningField: true, defaultTemperature: 0.6 },
        { match: "deepseek-reasoner", supportsInlineThinking: true,
            supportsReasoningField: true, defaultTemperature: 0.6 },
        { match: "qwq", supportsInlineThinking: true,
            defaultTemperature: 0.6 },
        { match: "qwen3", supportsInlineThinking: true,
            supportsToolChoiceRequired: false, defaultTemperature: 0.7 },
        { match: "minimax-m2", supportsInlineThinking: true,
            defaultTemperature: 0.6 },
        { match: "gemma3", supportsInlineThinking: true,
            supportsToolChoiceRequired: false, defaultTemperature: 0.7 },
        { match: "gemma2", supportsInlineThinking: true,
            supportsToolChoiceRequired: false, defaultTemperature: 0.7 },
        { match: "gemma", supportsInlineThinking: true,
            supportsToolChoiceRequired: false, defaultTemperature: 0.7 },
        { match: "phi-4", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        { match: "phi-3", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        // ── Llama-3 family — tool_choice:required often ignored ──
        { match: "llama-3.2", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        { match: "llama-3.1", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        { match: "llama3", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        // ── Mistral — `tool_choice: required` is documented but
        // frequently returns empty on small variants. ──
        { match: "mistral", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        { match: "mixtral", supportsToolChoiceRequired: false,
            defaultTemperature: 0.7 },
        // ── OpenAI reasoning — fixed temperature, max_completion_tokens ──
        { match: "o1", defaultTemperature: -1, supportsToolChoiceRequired: true },
        { match: "o3", defaultTemperature: -1, supportsToolChoiceRequired: true },
        { match: "o4", defaultTemperature: -1, supportsToolChoiceRequired: true },
        { match: "gpt-5", defaultTemperature: -1, supportsToolChoiceRequired: true }
    ]

    // Return the overrides that apply to a given model name, or null
    // when none of the known families match. Longest matching prefix
    // wins (see _matchModelFamily).
    function modelFamilyOverrides(modelName) {
        return root._matchModelFamily(modelName);
    }
    function _matchModelFamily(modelName) {
        if (!modelName) return null;
        let n = String(modelName).toLowerCase();
        let best = null;
        let bestLen = -1;
        for (let i = 0; i < _modelFamilyHints.length; i++) {
            let m = _modelFamilyHints[i].match;
            if (n.indexOf(m) >= 0 && m.length > bestLen) {
                best = _modelFamilyHints[i];
                bestLen = m.length;
            }
        }
        return best;
    }

    // Resolve a model name to a {temperature, supportsToolChoiceRequired,
    // supportsInlineThinking, supportsReasoningField} record. Layered
    // so subclass-level properties (e.g. DeepSeekApiStrategy's
    // `supportsReasoningField: true`) win when the model isn't in the
    // family table.
    function resolveModelCapabilities(modelObj) {
        let name = (modelObj && modelObj.model) || "";
        let family = root._matchModelFamily(name);
        return {
            // -1 sentinel = "omit temperature, let provider pick".
            temperature: family && "defaultTemperature" in family
                ? family.defaultTemperature : 0.7,
            supportsToolChoiceRequired: family
                ? family.supportsToolChoiceRequired
                : root.supportsToolChoiceRequired,
            supportsInlineThinking: family
                ? !!family.supportsInlineThinking
                : root.supportsInlineThinking,
            supportsReasoningField: family
                ? !!family.supportsReasoningField
                : root.supportsReasoningField
        };
    }

    // Live capability record for the active model — populated by
    // ModelCapabilityProbe on model switch. Strategies consume this
    // in getBody() to decide whether to include tools, set
    // temperature, and emit thinking-tag stripping. When null the
    // strategy falls back to the family-name heuristic (resolveModelCapabilities).
    property var activeCapabilities: null

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

    // Resolve effective capabilities by combining (in priority order):
    //   1. activeCapabilities (live probe result) — the model itself
    //      told us what it supports.
    //   2. resolveModelCapabilities (family-name heuristic) — used
    //      only when the probe hasn't completed yet or didn't return
    //      a record. Documented fallback; not the primary path.
    // Returns a normalised record the strategy can read with no
    // nulls in the middle.
    function _effectiveCaps(modelObj) {
        let ac = root.activeCapabilities;
        if (ac && typeof ac === "object") {
            return {
                temperature: typeof ac.temperature === "number"
                    ? ac.temperature : 0.7,
                supportsToolChoiceRequired: ac.supportsToolChoiceRequired !== false,
                supportsInlineThinking: !!ac.supportsInlineThinking,
                supportsReasoningField: !!ac.supportsReasoningField
            };
        }
        let fam = root.resolveModelCapabilities(modelObj);
        return {
            temperature: fam.temperature,
            supportsToolChoiceRequired: fam.supportsToolChoiceRequired,
            supportsInlineThinking: fam.supportsInlineThinking,
            supportsReasoningField: fam.supportsReasoningField
        };
    }

    // Strip an inline  `<think>...</think>` (or `### Reasoning` /
    // `### Response` headings) block from a chunk of model output.
    //
    // Models like qwen3, gemma2/3 (in thinking mode), DeepSeek-R1,
    // and qwq wrap their chain-of-thought in a `<think>...</think>`
    // block before the user-facing answer. Without this pass the chat
    // either shows the thinking as visible text (noisy) or the user
    // sees an empty completion followed by the answer on the next turn
    // (worse — looks like the model stalled). We split the chunk so
    // the UI can surface the thinking in a collapsible card and the
    // visible content is what gets sent back to the model.
    //
    // Returns { content, reasoningContent, wasTrimmed }.
    //
    // The "trim from the end" logic avoids splitting a chunk in the
    // middle of a `<think>` or `</think>` tag — if the chunk ends with
    // a partial opening tag we hold it back so the next chunk can
    // complete it.
    function splitInlineThinking(text) {
        if (!text)
            return { content: text || "", reasoningContent: "", wasTrimmed: false };
        let t = String(text);
        let thinkRe = /<think(?:ing)?>([\s\S]*?)<\/think(?:ing)?>/gi;
        let headingsRe = /^###\s*Reasoning\s*\n([\s\S]*?)\n###\s*(?:Response|Answer)\s*\n?/i;
        let reasoning = "";
        let cleaned = t;
        let m = headingsRe.exec(t);
        if (m) {
            reasoning += (reasoning ? "\n" : "") + m[1].trim();
            cleaned = t.slice(0, m.index) + t.slice(m.index + m[0].length);
        }
        let lastIndex = 0;
        let replace = (match, body) => {
            reasoning += (reasoning ? "\n" : "") + body.trim();
            return "";
        };
        // Use replace with a function so we can keep iterating across
        // multiple think blocks in the same chunk (qwen3 sometimes
        // emits several before the final answer).
        cleaned = cleaned.replace(thinkRe, replace);
        return {
            content: cleaned,
            reasoningContent: reasoning,
            wasTrimmed: reasoning.length > 0
        };
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
