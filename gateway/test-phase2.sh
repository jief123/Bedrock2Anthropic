#!/bin/bash
# Phase 2/3: Protocol Translation Test Suite
# Tests generated from Phase 1 inventory, ordered by risk priority

PASS=0
FAIL=0
BASE="http://localhost:8080/v1/messages"
KEY="gw-test-key-001"

assert_status() {
    local test_name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $test_name (HTTP $actual)"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $test_name (expected HTTP $expected, got HTTP $actual)"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    local test_name="$1" expected="$2" body="$3"
    if echo "$body" | grep -q "$expected"; then
        echo "  PASS: $test_name"
        PASS=$((PASS+1))
    else
        echo "  FAIL: $test_name (expected to contain '$expected')"
        echo "    Body: $(echo "$body" | head -3)"
        FAIL=$((FAIL+1))
    fi
}

echo "========================================="
echo "P0: Error Code Mapping (E5/E6/E7)"
echo "========================================="

echo ""
echo "--- E5: Bedrock 400 (invalid model) should return 400 ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"nonexistent-model-xyz","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
assert_status "E5: invalid model → 400" "400" "$STATUS"
assert_contains "E5: error type is invalid_request_error" "invalid_request_error" "$BODY"

echo ""
echo "--- E10: Malformed JSON → 400 ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{this is not json}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
assert_status "E10: malformed JSON → 400" "400" "$STATUS"

echo ""
echo "--- E11: Missing model field → 400 ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
assert_status "E11: missing model → 400" "400" "$STATUS"
assert_contains "E11: mentions model" "model" "$BODY"

echo ""
echo "========================================="
echo "P0: Auth & Rate Limit (E1/E2/E3)"
echo "========================================="

echo ""
echo "--- E1: Missing API key → 401 ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
STATUS=$(echo "$RESP" | tail -1)
assert_status "E1: no api key → 401" "401" "$STATUS"

echo ""
echo "--- E2: Invalid API key → 403 ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "x-api-key: bad-key" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
STATUS=$(echo "$RESP" | tail -1)
assert_status "E2: bad api key → 403" "403" "$STATUS"

echo ""
echo "========================================="
echo "P0: Control Modes (M1/M2)"
echo "========================================="

echo ""
echo "--- M1: Non-streaming happy path ---"
RESP=$(curl -s -w "\n%{http_code}" $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":50,"messages":[{"role":"user","content":"Say OK"}]}')
STATUS=$(echo "$RESP" | tail -1)
BODY=$(echo "$RESP" | sed '$d')
assert_status "M1: non-streaming → 200" "200" "$STATUS"
assert_contains "M1: has content array" '"content"' "$BODY"
assert_contains "M1: has usage" '"usage"' "$BODY"
assert_contains "M1: stop_reason present" '"stop_reason"' "$BODY"
assert_contains "M1: type is message" '"type":"message"' "$BODY"

echo ""
echo "--- M2: Streaming happy path ---"
STREAM_OUT=$(curl -s -N $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":50,"stream":true,"messages":[{"role":"user","content":"Say OK"}]}' 2>&1)
assert_contains "M2: has message_start" "message_start" "$STREAM_OUT"
assert_contains "M2: has content_block_start" "content_block_start" "$STREAM_OUT"
assert_contains "M2: has content_block_delta" "content_block_delta" "$STREAM_OUT"
assert_contains "M2: has message_delta" "message_delta" "$STREAM_OUT"
assert_contains "M2: has message_stop" "message_stop" "$STREAM_OUT"
assert_contains "M2: SSE event: prefix" "event: " "$STREAM_OUT"
assert_contains "M2: SSE data: prefix" "data: " "$STREAM_OUT"

echo ""
echo "========================================="
echo "P1: Data Mappings"
echo "========================================="

echo ""
echo "--- D1: Model mapping ---"
RESP=$(curl -s $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}')
assert_contains "D1: response has model field" '"model"' "$RESP"

echo ""
echo "--- D3: anthropic_version injected ---"
# If anthropic_version wasn't injected, Bedrock would reject the request
# A successful call proves D3 works
assert_contains "D3: successful call proves version injection" '"type":"message"' "$RESP"

echo ""
echo "--- D4: Beta header conversion ---"
RESP=$(curl -s $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -H "anthropic-beta: token-efficient-tools-2025-02-19" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":50,"tools":[{"name":"test","description":"test","input_schema":{"type":"object","properties":{}}}],"messages":[{"role":"user","content":"hi"}]}')
assert_contains "D4: beta header accepted (no error)" '"type":"message"' "$RESP"

echo ""
echo "========================================="
echo "P1: Tool Use"
echo "========================================="

echo ""
echo "--- D18: Tool use pass-through ---"
RESP=$(curl -s $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":200,"tools":[{"name":"get_weather","description":"Get weather","input_schema":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}],"messages":[{"role":"user","content":"What is the weather in Tokyo?"}]}')
assert_contains "D18: tool_use in response" "tool_use" "$RESP"
assert_contains "D18: stop_reason is tool_use" '"stop_reason":"tool_use"' "$RESP"

echo ""
echo "========================================="
echo "P1: Extended Thinking"
echo "========================================="

echo ""
echo "--- D20: Thinking pass-through ---"
RESP=$(curl -s $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5-20250929","max_tokens":4000,"thinking":{"type":"enabled","budget_tokens":1024},"messages":[{"role":"user","content":"What is 2+2?"}]}')
assert_contains "D20: thinking block in response" '"type":"thinking"' "$RESP"
assert_contains "D20: signature present" '"signature"' "$RESP"
assert_contains "D20: text block in response" '"type":"text"' "$RESP"

echo ""
echo "========================================="
echo "P1: Multimodal"
echo "========================================="

echo ""
echo "--- D12: Image content pass-through ---"
IMG="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
RESP=$(curl -s $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":50,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"${IMG}\"}},{\"type\":\"text\",\"text\":\"Describe this.\"}]}]}")
assert_contains "D12: multimodal response" '"type":"message"' "$RESP"

echo ""
echo "========================================="
echo "P2: Streaming + Thinking combo"
echo "========================================="

echo ""
echo "--- M2×D20: Streaming with thinking ---"
STREAM_OUT=$(curl -s -N $BASE \
  -H "x-api-key: $KEY" -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5-20250929","max_tokens":4000,"stream":true,"thinking":{"type":"enabled","budget_tokens":1024},"messages":[{"role":"user","content":"What is 3+3?"}]}' 2>&1)
assert_contains "M2×D20: thinking_delta in stream" "thinking_delta" "$STREAM_OUT"
assert_contains "M2×D20: text_delta in stream" "text_delta" "$STREAM_OUT"
assert_contains "M2×D20: signature_delta in stream" "signature_delta" "$STREAM_OUT"

echo ""
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS+FAIL))"
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
fi
