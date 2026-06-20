import QtQuick

ApiStrategy {
    supportsStreaming: true

    function getEndpoint(modelObj, apiKey) {
        return modelObj.endpoint || "https://api.anthropic.com/v1/messages";
    }

    function getHeaders(apiKey) {
        return [
            "Content-Type: application/json",
            "x-api-key: " + apiKey,
            "anthropic-version: 2023-06-01",
            "anthropic-beta: prompt-caching-2024-07-31"
        ];
    }

    function _extractSystemPrompt(messages) {
        for (let i = 0; i < messages.length; i++) {
            if (messages[i].role === "system")
                return messages[i].content;
        }
        return "";
    }

    function _filterMessages(messages) {
        let filtered = [];
        for (let i = 0; i < messages.length; i++) {
            if (messages[i].role === "system")
                continue;
            let msg = messages[i];
            let role = msg.role;

            // Assistant message that proposed a tool call — Anthropic
            // expects a "tool_use" content block, not a functionCall blob.
            if (role === "assistant" && msg.functionCall) {
                let contentBlocks = [];
                if (msg.content)
                    contentBlocks.push({ type: "text", text: msg.content });
                contentBlocks.push({
                    type: "tool_use",
                    id: msg.toolCallId || msg.functionCall.tool_call_id || ("tu_" + Math.random().toString(36).slice(2)),
                    name: msg.functionCall.name || "",
                    input: msg.functionCall.args || {}
                });
                filtered.push({ role: "assistant", content: contentBlocks });
                continue;
            }

            // Tool result — Anthropic expects a "tool_result" content
            // block inside a user message.
            if (role === "function" || role === "tool") {
                let toolUseId = msg.tool_call_id || msg.toolCallId || "";
                filtered.push({
                    role: "user",
                    content: [{
                        type: "tool_result",
                        tool_use_id: toolUseId,
                        content: msg.content || ""
                    }]
                });
                continue;
            }

            if (msg.attachments && msg.attachments.length > 0) {
                let contentParts = [];
                for (let j = 0; j < msg.attachments.length; j++) {
                    let att = msg.attachments[j];
                    if (att.type === "image") {
                        contentParts.push({
                            type: "image",
                            source: {
                                type: "base64",
                                media_type: att.mimeType,
                                data: att.base64
                            }
                        });
                    }
                }
                contentParts.push({ type: "text", text: msg.content || "" });
                filtered.push({ role: role, content: contentParts });
            } else {
                filtered.push({
                    role: role,
                    content: msg.content || ""
                });
            }
        }
        return filtered;
    }

    function getBody(messages, model, tools, options) {
        let body = {
            model: model.model,
            messages: _filterMessages(messages),
            max_tokens: 4096,
            temperature: 0.7
        };

        let sysPrompt = _extractSystemPrompt(messages);
        if (sysPrompt) {
            // Prompt caching: always attach cache_control to the
            // system block. Anthropic's cache-write premium is
            // negligible (<5% of normal prompt tokens) and ANY
            // cache hit on subsequent turns drops first-token
            // latency by 60-90%. The previous threshold (>4000
            // chars) was conservative for paid users; for the
            // chat pattern the system prompt is always repeated,
            // so always caching is the right default.
            body.system = [{
                type: "text",
                text: sysPrompt,
                cache_control: { type: "ephemeral" }
            }];
        }

        if (tools && tools.length > 0) {
            // Tools block changes only when the agent registry
            // changes — i.e. rarely across a session. Caching it
            // turns every subsequent turn's tool-schema cost from
            // ~500 input tokens into ~50 cached tokens.
            body.tools = tools.map((t, i) => {
                let entry = {
                    name: t.name,
                    description: t.description,
                    input_schema: t.parameters
                };
                // Mark the LAST tool with cache_control so Anthropic
                // caches the entire tool list (cache_breakpoint on
                // a single element caches everything before it).
                if (i === tools.length - 1) {
                    entry.cache_control = { type: "ephemeral" };
                }
                return entry;
            });
        }

        return body;
    }

    function getStreamBody(messages, model, tools, options) {
        let body = getBody(messages, model, tools);
        body.stream = true;
        return body;
    }

    function parseResponse(response) {
        try {
            let json = JSON.parse(response);

            if (json.error)
                return { content: "API Error: " + json.error.message };

            if (json.type === "error")
                return { content: "API Error: " + (json.error ? json.error.message : "Unknown error") };

            if (json.content && json.content.length > 0) {
                let textContent = "";
                let funcCall = null;

                for (let i = 0; i < json.content.length; i++) {
                    let block = json.content[i];
                    if (block.type === "text")
                        textContent += block.text;
                    if (block.type === "tool_use") {
                        funcCall = {
                            name: block.name,
                            args: block.input
                        };
                    }
                }

                if (funcCall)
                    return { content: textContent, functionCall: funcCall };
                return { content: textContent };
            }

            return { content: "Error: No content in response." };
        } catch (e) {
            return { content: "Error parsing response: " + e.message };
        }
    }

    function parseStreamChunk(line) {
        let trimmed = line.trim();
        if (trimmed === "")
            return { content: "", done: false, error: null };

        // Anthropic SSE uses "event:" lines followed by "data:" lines
        if (trimmed.startsWith("event:")) {
            let eventType = trimmed.substring(7).trim();
            if (eventType === "message_stop")
                return { content: "", done: true, error: null };
            if (eventType === "error")
                return { content: "", done: false, error: "Stream error" };
            return { content: "", done: false, error: null };
        }

        if (!trimmed.startsWith("data: "))
            return { content: "", done: false, error: null };

        try {
            let json = JSON.parse(trimmed.substring(6));

            if (json.type === "content_block_delta") {
                if (json.delta && json.delta.type === "text_delta")
                    return { content: json.delta.text || "", done: false, error: null };
            }

            if (json.type === "message_delta") {
                if (json.delta && json.delta.stop_reason)
                    return { content: "", done: true, error: null };
            }

            if (json.type === "error")
                return { content: "", done: false, error: json.error ? json.error.message : "Unknown error" };

            return { content: "", done: false, error: null };
        } catch (e) {
            return { content: "", done: false, error: null };
        }
    }
}
