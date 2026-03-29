#!/bin/bash
# Test streaming
curl -N http://localhost:8080/v1/messages \
  -H "x-api-key: gw-test-key-001" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-haiku-4-5-20251001",
    "max_tokens": 200,
    "stream": true,
    "messages": [
        {"role": "user", "content": "Count from 1 to 5, one number per line."}
    ]
  }'
