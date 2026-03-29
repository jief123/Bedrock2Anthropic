#!/bin/bash
curl -s http://localhost:8080/v1/messages \
  -H "x-api-key: gw-test-key-001" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 100,
    "messages": [
        {"role": "user", "content": "Say hello in 3 words."}
    ]
  }' | python3 -m json.tool
