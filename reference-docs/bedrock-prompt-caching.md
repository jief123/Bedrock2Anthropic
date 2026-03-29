# Bedrock Prompt Caching

Source: https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html
Downloaded: 2026-03-28

---

## Supported Models & Limits

| Model | Model ID | Min tokens/checkpoint | Max checkpoints | TTL |
|---|---|---|---|---|
| Claude Opus 4.5 | anthropic.claude-opus-4-5-20251101-v1:0 | 4,096 | 4 | 5min, 1h |
| Claude Opus 4.1 | anthropic.claude-opus-4-1-20250805-v1:0 | 1,024 | 4 | 5min |
| Claude Opus 4 | anthropic.claude-opus-4-20250514-v1:0 | 1,024 | 4 | 5min |
| Claude Sonnet 4.5 | anthropic.claude-sonnet-4-5-20250929-v1:0 | 1,024 | 4 | 5min, 1h |
| Claude Haiku 4.5 | anthropic.claude-haiku-4-5-20251001-v1:0 | 4,096 | 4 | 5min, 1h |
| Claude Sonnet 4 | anthropic.claude-sonnet-4-20250514-v1:0 | 1,024 | 4 | 5min |
| Claude 3.7 Sonnet | anthropic.claude-3-7-sonnet-20250219-v1:0 | 1,024 | 4 | 5min |

Cacheable fields: `system`, `messages`, `tools`

## InvokeModel API Format (Claude)

```json
{
    "anthropic_version": "bedrock-2023-05-31",
    "system": "Reply concisely",
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": "Long document content..."
                },
                {
                    "type": "text",
                    "text": "Everything before this is cached",
                    "cache_control": {
                        "type": "ephemeral"
                    }
                }
            ]
        }
    ],
    "max_tokens": 2048
}
```

## TTL Configuration

```json
"cache_control": {
    "type": "ephemeral",
    "ttl": "1h"
}
```

- Default: 5 minutes
- 1h TTL: Only Opus 4.5, Sonnet 4.5, Haiku 4.5
- Mixed TTL: Longer TTL must appear BEFORE shorter TTL

## Simplified Cache Management

- Place single checkpoint at end of static content
- System auto-checks ~20 content blocks backwards
- Finds longest matching prefix automatically
- For more control, use multiple explicit checkpoints (up to 4)

## Response Metrics

### Converse API
- `CacheReadInputTokens`
- `CacheWriteInputTokens`
- `CacheDetails` (TTL info)

### InvokeModel API
- `cache_creation_input_tokens`
- `cache_read_input_tokens`
- `cache_creation.ephemeral_5m_input_tokens`
- `cache_creation.ephemeral_1h_input_tokens`

## Pricing

- Cache write: Higher than standard input token price
- Cache read: Lower than standard input token price
- Cache hits: NOT counted against rate limit
- Supports Cross-region Inference
