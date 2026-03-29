# Bedrock Claude Extended Thinking

Source: https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-extended-thinking.html
Downloaded: 2026-03-28

---

## Supported Models

| Model | Model ID |
|---|---|
| Claude Opus 4.5 | anthropic.claude-opus-4-5-20251101-v1:0 |
| Claude Opus 4 | anthropic.claude-opus-4-20250514-v1:0 |
| Claude Sonnet 4 | anthropic.claude-sonnet-4-20250514-v1:0 |
| Claude Sonnet 4.5 | anthropic.claude-sonnet-4-5-20250929-v1:0 |
| Claude Haiku 4.5 | anthropic.claude-haiku-4-5-20251001-v1:0 |
| Claude 3.7 Sonnet | anthropic.claude-3-7-sonnet-20250219-v1:0 |

## Request Format

```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 10000,
    "thinking": {
        "type": "enabled",
        "budget_tokens": 4000
    },
    "messages": [...]
}
```

## Response Format

```json
{
    "content": [
        {
            "type": "thinking",
            "thinking": "Let me analyze this step by step...",
            "signature": "WaUjzkypQ2mUEVM36O2TxuC06KN8xyfbJwyem2dw3URve..."
        },
        {
            "type": "text",
            "text": "Based on my analysis..."
        }
    ]
}
```

## Key Constraints

- Thinking NOT compatible with `temperature`, `top_p`, `top_k` modifications
- Cannot pre-fill responses when thinking is enabled
- `budget_tokens` must be < `max_tokens` (except with interleaved thinking)
- Minimum budget: 1,024 tokens
- Streaming REQUIRED when `max_tokens` > 21,333
- Tool use with thinking only supports `tool_choice: any`

## Summarized Thinking (Claude 4+)

- Claude 4 models return summarized thinking (not full)
- Charged for full thinking tokens, not summary tokens
- Claude 3.7 Sonnet still returns full thinking output
- Full thinking available via `dev-full-thinking-2025-05-14` beta

## Streaming Events

```
event: content_block_start → {"type": "thinking", "thinking": ""}
event: content_block_delta → {"type": "thinking_delta", "thinking": "..."}
event: content_block_delta → {"type": "signature_delta", "signature": "..."}
event: content_block_stop
event: content_block_start → {"type": "text", "text": ""}
event: content_block_delta → {"type": "text_delta", "text": "..."}
```

## Interleaved Thinking (Beta)

Beta header: `interleaved-thinking-2025-05-14`
- Claude 4+ models
- Think between tool calls
- budget_tokens can exceed max_tokens

## Thinking Block Clearing (Beta)

Beta header: `context-management-2025-06-27`
- Supported: Claude Sonnet 4/4.5, Haiku 4.5, Opus 4/4.1/4.5
- Strategy: `clear_thinking_20251015`
- Config: `keep` (default: 1 thinking turn)

## Context Window Calculation

```
context_window = (current_input_tokens - previous_thinking_tokens) + (thinking_tokens + encrypted_thinking_tokens + text_output_tokens)
```

Previous thinking blocks are removed and NOT counted towards context window.
