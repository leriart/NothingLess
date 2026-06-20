import QtQuick

// DeepSeek API — OpenAI-compatible format with reasoning support (R1).
//
// Quirks handled here:
//   - `parallel_tool_calls` is rejected by DeepSeek (their docs are
//     explicit — only one tool call per assistant turn). Override
//     supportsParallelToolCalls=false so the request body builder
//     omits / sets the field appropriately.
//   - DeepSeek's R1 reasoner occasionally returns empty `content`
//     after a tool result and ignores the standard `tool_choice:
//     "required"` nudge. We keep `defaultToolChoice = "auto"` here;
//     Ai.qml's nudge layer detects the empty completion and retries
//     with a stronger textual nudge that the model does follow.
OpenAiCompatibleStrategy {
    defaultBaseEndpoint: "https://api.deepseek.com"
    supportsReasoning: true
    reasoningField: "reasoning_content"
    supportsParallelToolCalls: false
    defaultToolChoice: "auto"
}
