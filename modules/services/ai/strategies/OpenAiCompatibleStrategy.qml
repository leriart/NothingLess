import QtQuick

// Robust OpenAI-compatible chat completions strategy.
// Used directly or subclassed by OpenAI, Mistral, Groq, DeepSeek, etc.
ApiStrategy {
    id: root

    supportsStreaming: true
    supportsReasoning: false
    supportsVision: true

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

    function getBody(messages, model, tools) {
        let body = {
            model: model.model,
            messages: formatMessages(messages),
            temperature: 0.7
        };

        let toolList = formatTools(tools);
        if (toolList.length > 0) {
            body.tools = toolList;
        }

        return body;
    }

    function getStreamBody(messages, model, tools) {
        let body = getBody(messages, model, tools);
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
                    result.functionCall = {
                        name: tc.function.name,
                        args: JSON.parse(tc.function.arguments)
                    };
                    result.toolCallId = tc.id || "";
                }

                if (root.supportsReasoning && msg.reasoning_content)
                    result.reasoningContent = msg.reasoning_content;

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

                if (delta && delta.content)
                    result.content = delta.content;

                if (root.supportsReasoning && delta && delta.reasoning_content)
                    result.reasoningContent = delta.reasoning_content;

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
