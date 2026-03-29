#!/bin/bash
# Test extended thinking
curl -s http://localhost:8080/v1/messages \
  -H "x-api-key: gw-test-key-001" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 8000,
    "thinking": {
        "type": "enabled",
        "budget_tokens": 2000
    },
    "messages": [
        {"role": "user", "content": "What is 27 * 453?"}
    ]
  }' | python3 -m json.tool
