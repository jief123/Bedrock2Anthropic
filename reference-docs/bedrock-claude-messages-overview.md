# Bedrock Claude Messages API - Overview & Request/Response

Source: https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html
Source: https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages-request-response.html
Downloaded: 2026-03-28

---

## Request Schema

```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "anthropic_beta": ["computer-use-2024-10-22"],
    "max_tokens": int,
    "system": string,
    "messages": [
        {
            "role": string,
            "content": [
                { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "..." } },
                { "type": "text", "text": "content text" }
            ]
        }
    ],
    "temperature": float,
    "top_p": float,
    "top_k": int,
    "tools": [...],
    "tool_choice": { "type": string, "name": string },
    "stop_sequences": [string]
}
```

## Required Parameters

- **anthropic_version**: Must be `bedrock-2023-05-31`
- **max_tokens**: Maximum tokens to generate
- **messages**: Input messages array
  - role: `user` or `assistant`
  - content: array of text/image blocks

## Optional Parameters

- **system**: System prompt
- **anthropic_beta**: Beta feature headers
- **stop_sequences**: Custom stop sequences (max 8191)
- **temperature**: 0-1, default 1
- **top_p**: 0-1, default 0.999
- **top_k**: 0-500, disabled by default
- **tools**: Tool definitions
- **tool_choice**: `any`, `auto`, `tool`, or `none`

## Beta Headers

| Beta feature | Beta header | Notes |
|---|---|---|
| Computer use | `computer-use-2025-01-24` | Claude 3.7 Sonnet |
| Tool use | `token-efficient-tools-2025-02-19` | Claude 3.7+ |
| Interleaved thinking | `interleaved-thinking-2025-05-14` | Claude 4+ |
| 128K output | `output-128k-2025-02-19` | Claude 3.7 Sonnet |
| Dev full thinking | `dev-full-thinking-2025-05-14` | Claude 4+ |
| 1M context | `context-1m-2025-08-07` | Claude Sonnet 4 |
| Context management | `context-management-2025-06-27` | Claude Sonnet 4.5, Haiku 4.5 |
| Effort | `effort-2025-11-24` | Claude Opus 4.5 |
| Tool search | `tool-search-tool-2025-10-19` | Claude Opus 4.5 |
| Tool examples | `tool-examples-2025-10-29` | Claude Opus 4.5 |

## Response Schema

```json
{
    "id": string,
    "model": string,
    "type": "message",
    "role": "assistant",
    "content": [
        { "type": "text", "text": string },
        { "type": "tool_use", "id": string, "name": string, "input": json },
        { "type": "image", "source": json }
    ],
    "stop_reason": string,
    "stop_sequence": string,
    "usage": {
        "input_tokens": integer,
        "output_tokens": integer
    }
}
```

## stop_reason Values

- `end_turn` - Natural stopping point
- `max_tokens` - Exceeded max_tokens
- `stop_sequence` - Hit custom stop sequence
- `refusal` - Safety refusal
- `tool_use` - Tool call requested
- `model_context_window_exceeded` - Context window limit (Claude Sonnet 4.5+)

## Effort Parameter (Beta)

Requires beta header `effort-2025-11-24`. For Claude Opus 4.5.

```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "anthropic_beta": ["effort-2025-11-24"],
    "max_tokens": 4096,
    "output_config": { "effort": "medium" },
    "messages": [...]
}
```

Effort levels: `high` (default), `medium`, `low`

## Warning

Claude Sonnet 4.5 and Claude Haiku 4.5: specify either `temperature` or `top_p`, not both.
