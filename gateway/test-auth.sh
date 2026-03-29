#!/bin/bash
echo "=== Test: Missing API key ==="
curl -s http://localhost:8080/v1/messages \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' | python3 -m json.tool

echo ""
echo "=== Test: Invalid API key ==="
curl -s http://localhost:8080/v1/messages \
  -H "x-api-key: invalid-key" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' | python3 -m json.tool

echo ""
echo "=== Test: Valid API key ==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:8080/v1/messages \
  -H "x-api-key: gw-test-key-001" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
