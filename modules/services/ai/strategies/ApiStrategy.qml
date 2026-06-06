import QtQuick

// Base interface / helper for all AI provider strategies.
// Subclasses override getEndpoint, getHeaders, and parse methods.
QtObject {
    id: root

    property bool supportsStreaming: true
    property bool supportsReasoning: false
    property bool supportsVision: true
    property string reasoningField: "" // e.g. "reasoning_content" for DeepSeek

    function getEndpoint(modelObj, apiKey) { return ""; }
    function getHeaders(apiKey) { return []; }

    function getBody(messages, model, tools) { return {}; }
    function getStreamBody(messages, model, tools) {
        let body = getBody(messages, model, tools);
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

    // Format internal messages (with attachments) to OpenAI-compatible content parts.
    function formatMessages(messages) {
        let formatted = [];
        for (let i = 0; i < messages.length; i++) {
            let msg = messages[i];
            if (msg.attachments && msg.attachments.length > 0) {
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
                formatted.push({ role: msg.role, content: contentParts });
            } else {
                formatted.push({ role: msg.role, content: msg.content || "" });
            }
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
