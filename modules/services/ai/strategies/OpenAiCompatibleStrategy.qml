import QtQuick

// Robust OpenAI-compatible chat completions strategy.
// Used directly or subclassed by OpenAI, Mistral, Groq, DeepSeek, etc.
ApiStrategy {
    id: root

    supportsStreaming: true
    supportsReasoning: false
    supportsVision: true

    // The currently-active model's resolved capability record.
    // Refreshed by Ai.qml via `activeCapabilities` when the probe
    // completes. Falls back to the family heuristic when null.
    property var _caps: ({ temperature: 0.7,
        supportsToolChoiceRequired: true,
        supportsInlineThinking: false,
        supportsReasoningField: false })

    // Subclasses can override the base API endpoint.
    property string defaultBaseEndpoint: "https://api.openai.com"

    function getEndpoint(modelObj, apiKey) {
        let base = modelObj.endpoint || defaultBaseEndpoint;
        return normalizeChatEndpoint(base);
    }

    function getHeaders(apiKey) {
        return [
            "Content-Type: application/json",
            "Authorization: Bearer " + apiKey
        ];
    }

    function getBody(messages, model, tools, options) {
        // Per-model capabilities come from ModelCapabilityProbe via
        // `root.activeCapabilities` when the probe has completed.
        // The family-name heuristic in `_effectiveCaps(model)` is
        // the documented fallback for the first request before the
        // probe fires. The probe is fire-and-forget, so the very
        // first chat round-trip uses the heuristic; every subsequent
        // one uses the probed record (and refines it via
        // recordOutcome()).
        _caps = root._effectiveCaps(model);

        let body = {
            model: model.model,
            messages: formatMessages(messages),
        };

        // Temperature: -1 sentinel in the family table means "omit
        // temperature, let the provider pick the default". Applies to
        // reasoning models (o1/o3/gpt-5) that hard-400 on any explicit
        // value. 0 is treated as "explicit 0" (the family table never
        // returns 0 — it uses -1 for the omit case).
        if (typeof _caps.temperature === "number" && _caps.temperature >= 0) {
            body.temperature = _caps.temperature;
        }

        let toolList = formatTools(tools);
        if (toolList.length > 0) {
            // Honour the live probe: when the model itself reported
            // `supportsTools: false` (Ollama's /api/show `capabilities`
            // didn't list "tools"), skip the tools field entirely.
            // Tiny local models (qwen2.5:0.5b, llama-3.2-1b) return
            // empty completions when they see a tools field they can't
            // parse, so matching the model's own report keeps the
            // chain alive. Text-based intent detection
            // (`_detectTextToolCall` in Ai.qml) still works because
            // those models emit tool calls as plain text.
            if (root.activeCapabilities
                    && root.activeCapabilities.supportsTools === false) {
                toolList = [];
            }
            if (toolList.length > 0) {
                body.tools = toolList;
            }
            // ── tool_choice ──
            // OpenAI-compatible providers (DeepSeek, Mistral, Groq, ...)
            // default to "auto" if this field is omitted, but setting it
            // explicitly avoids gateway-specific quirks where some
            // proxies drop the field. The `options` arg carries the
            // nudging strategy from Ai.qml: when the previous turn
            // returned an empty completion after a tool result, we set
            // tool_choice to "required" so the model MUST call a tool
            // (and so can't return another empty text-only response
            // and stall the chain).
            //
            // BUT — Gemma / Llama-3 / Qwen3 / Mistral families don't
            // honour `tool_choice: "required"` and instead return an
            // empty completion, which is the user-visible "empty
            // response" bug. The per-family table flags those as
            // supportsToolChoiceRequired:false; we degrade gracefully
            // to a textual nudge (added by Ai.qml's nudge layer) rather
            // than forcing the field.
            let requested = (options && options.toolChoice)
                ? options.toolChoice
                : root.defaultToolChoice;
            let tc = _caps.supportsToolChoiceRequired
                ? resolveToolChoice(requested, null)
                : resolveToolChoice("auto", null);
            body.tool_choice = tc;
            // ── parallel_tool_calls ──
            // Allow multiple tool calls in one assistant turn. Defaults
            // to false for DeepSeek (its docs are explicit about not
            // supporting it), true elsewhere. Some OpenAI-compatible
            // gateways also reject the field outright — we set it
            // defensively so the field is always present and explicit.
            body.parallel_tool_calls = root.supportsParallelToolCalls;
        }

        return body;
    }

    function getStreamBody(messages, model, tools, options) {
        let body = getBody(messages, model, tools, options);
        body.stream = true;
        return body;
    }

    function parseResponse(response) {
        try {
            let json = JSON.parse(response);

            if (json.error)
                return { content: "API Error: " + (json.error.message || JSON.stringify(json.error)) };

            if (json.choices && json.choices.length > 0) {
                let msg = json.choices[0].message;
                let result = { content: msg.content || "" };

                if (msg.tool_calls && msg.tool_calls.length > 0) {
                    let tc = msg.tool_calls[0];
                    try {
                        var parsed = JSON.parse(tc.function.arguments);
                    } catch (e) {
                        parsed = {};
                    }
                    result.functionCall = {
                        name: tc.function.name,
                        args: parsed
                    };
                    result.toolCallId = tc.id || "";
                }

                // Reasoning-content field (DeepSeek R1, OpenAI o-series).
                // The family table enables this for those models and
                // _caps.supportsReasoningField mirrors it, so we don't
                // hard-code supportsReasoning here — the strategy-level
                // flag controls whether the request body asked for the
                // field at all.
                if (_caps && _caps.supportsReasoningField
                        && msg.reasoning_content) {
                    result.reasoningContent = msg.reasoning_content;
                }

                // Inline-think tag stripping. For Gemma2/3 (thinking
                // mode), Qwen3, DeepSeek-R1 (distilled), and qwq, the
                // chain-of-thought comes back wrapped in `...`
                // rather than a separate field. Without this pass the
                // visible content contains the whole reasoning block,
                // which is noisy and burns context on the next turn.
                if (_caps && _caps.supportsInlineThinking
                        && result.content) {
                    let split = splitInlineThinking(result.content);
                    result.content = split.content;
                    if (split.reasoningContent
                            && !result.reasoningContent) {
                        result.reasoningContent = split.reasoningContent;
                    }
                }

                return result;
            }

            return { content: "Error: No content in response." };
        } catch (e) {
            return { content: "Error parsing response: " + e.message };
        }
    }

    function parseStreamChunk(line) {
        let trimmed = line.trim();
        if (trimmed === "" || trimmed.startsWith("event:"))
            return emptyResult();

        if (trimmed === "data: [DONE]")
            return { content: "", done: true, error: null, reasoningContent: "", toolCallDelta: null, toolCallId: "" };

        if (!trimmed.startsWith("data: ")) {
            // Some providers send raw JSON errors when not streaming correctly.
            try {
                let json = JSON.parse(trimmed);
                if (json.error)
                    return { content: "", done: false, error: json.error.message || JSON.stringify(json.error), reasoningContent: "", toolCallDelta: null, toolCallId: "" };
            } catch (e) {}
            return emptyResult();
        }

        try {
            let json = JSON.parse(trimmed.substring(6));

            if (json.error)
                return { content: "", done: false, error: json.error.message || JSON.stringify(json.error), reasoningContent: "", toolCallDelta: null, toolCallId: "" };

            if (json.choices && json.choices.length > 0) {
                let delta = json.choices[0].delta;
                let result = emptyResult();

                let rawContent = (delta && delta.content) ? delta.content : "";

                // Inline-think tag stripping. Done per-chunk so a partial
                // `think` tag at the chunk boundary is held back rather
                // than leaked into the visible stream. See
                // splitInlineThinking for the regex.
                if (_caps && _caps.supportsInlineThinking
                        && rawContent) {
                    let split = splitInlineThinking(rawContent);
                    result.content = split.content;
                    if (split.reasoningContent) {
                        result.reasoningContent = (result.reasoningContent
                            || "") + split.reasoningContent;
                    }
                } else {
                    result.content = rawContent;
                }

                // Reasoning-content field (DeepSeek R1, OpenAI o-series).
                if (root.supportsReasoning && delta && delta.reasoning_content)
                    result.reasoningContent = (result.reasoningContent
                        || "") + delta.reasoning_content;

                if (delta && delta.tool_calls) {
                    result.toolCallDelta = delta.tool_calls;
                }

                if (json.choices[0].finish_reason)
                    result.done = true;

                return result;
            }

            return emptyResult();
        } catch (e) {
            return emptyResult();
        }
    }

    function emptyResult() {
        return { content: "", done: false, error: null, reasoningContent: "", toolCallDelta: null, toolCallId: "" };
    }
}
