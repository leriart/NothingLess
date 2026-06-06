import QtQuick

// DeepSeek API — OpenAI-compatible format with reasoning support (R1).
OpenAiCompatibleStrategy {
    defaultBaseEndpoint: "https://api.deepseek.com"
    supportsReasoning: true
    reasoningField: "reasoning_content"
}
