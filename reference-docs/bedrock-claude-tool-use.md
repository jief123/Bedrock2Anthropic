# Bedrock Claude Tool Use

Source: https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages-tool-use.html
Downloaded: 2026-03-28

---

## Custom Tools

```json
{
    "type": "custom",
    "name": "tool_name",
    "description": "...",
    "input_schema": { "type": "object", "properties": {...} }
}
```

## Anthropic Defined Tools

| Model | Tool | Type |
|---|---|---|
| Claude 4+ (Opus 4.1, Opus 4, Sonnet 4.5, Haiku 4.5, Sonnet 4) | Text Editor | `text_editor_20250124` |
| Claude 3.7 Sonnet | Computer | `computer_20250124` |
| Claude 3.7 Sonnet | Text Editor | `text_editor_20250124` |
| Claude 3.5 Sonnet v2 | Bash | `bash_20250124` |
| Claude 3.5 Sonnet v2 | Text Editor | `text_editor_20241022` |
| Claude 3.5 Sonnet v2 | Bash | `bash_20241022` |
| Claude 3.5 Sonnet v2 | Computer | `computer_20241022` |

## Computer Use (Beta)

Beta header: `computer-use-2025-01-24` (Claude 3.7+) or `computer-use-2024-10-22` (Claude 3.5 v2)

## Fine-grained Tool Streaming (Beta)

Beta header: `fine-grained-tool-streaming-2025-05-14`
- Supported: Claude Sonnet 4.5, Haiku 4.5, Sonnet 4, Opus 4
- Streams tool parameters without buffering/JSON validation
- Reduces latency for large parameters

## Automatic Tool Call Clearing (Beta)

Beta header: `context-management-2025-06-27`
- Strategy: `clear_tool_uses_20250919`
- Supported: Claude Sonnet 4/4.5, Haiku 4.5, Opus 4/4.1/4.5

Config options:
- `trigger`: When to activate (default: 100K input tokens)
- `keep`: Tool uses to keep (default: 3)
- `clear_at_least`: Minimum tokens to clear
- `exclude_tools`: Tools to never clear
- `clear_tool_inputs`: Clear tool call params too (default: false)

## Memory Tool (Beta)

Beta header: `context-management-2025-06-27`
- Supported: Claude Sonnet 4.5

```json
{ "type": "memory_20250818", "name": "memory" }
```

## Tool Search Tool (Beta)

Beta header: `tool-search-tool-2025-10-19`

Types:
- `tool_search_tool_regex` - Regex-based search
- Custom tool search (embedding-based)

Features:
- `defer_loading: true` on tools for lazy loading
- Returns `server_tool_use` and `tool_search_tool_result` blocks
- Supports custom tool search implementations

## Tool Use System Prompt Tokens

| Model | auto/none | any/tool |
|---|---|---|
| Claude 4+ / 3.7 / 3.5v2 | 346 | 313 |
| Claude 3.5 Sonnet | 294 | 261 |
| Claude 3 Opus | 530 | 281 |

## Tool Use Examples (Beta)

Beta header: `tool-examples-2025-10-29`
