# Bedrock Claude Adaptive Thinking

Source: https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html
Downloaded: 2026-03-28

---

## Supported Models

| Model | Model ID |
|---|---|
| Claude Opus 4.6 | anthropic.claude-opus-4-6-v1 |
| Claude Sonnet 4.6 | anthropic.claude-sonnet-4-6 |

## Key Points

- `thinking.type: "enabled"` and `budget_tokens` are DEPRECATED on Opus 4.6/Sonnet 4.6
- Use `thinking.type: "adaptive"` instead
- No beta header required
- Automatically enables interleaved thinking
- Older models do NOT support adaptive thinking

## Request Format

```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 16000,
    "thinking": {
        "type": "adaptive"
    },
    "messages": [...]
}
```

## Effort Levels with Adaptive Thinking

| Effort | Behavior |
|---|---|
| `max` | Always thinks, no constraints. Opus 4.6 ONLY |
| `high` (default) | Always thinks. Deep reasoning |
| `medium` | Moderate thinking. May skip for simple queries |
| `low` | Minimizes thinking. Skips for simple tasks |

## Prompt Caching

- Consecutive requests using `adaptive` preserve cache breakpoints
- Switching between `adaptive` and `enabled`/`disabled` BREAKS cache for messages
- System prompts and tool definitions remain cached regardless of mode changes
