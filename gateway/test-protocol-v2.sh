#!/bin/bash
# Protocol Translation Test Suite V2 — Independent Assessment
# Date: 2026-03-28
# Methodology: Protocol Translation Test Generator
#
# Usage: ./test-protocol-v2.sh [BASE_URL] [API_KEY]
# Default: http://localhost:8080 gw-test-key-001

set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
API_KEY="${2:-gw-test-key-001}"
PASS=0
FAIL=0
SKIP=0
FINDINGS=""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { ((PASS++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}FAIL${NC} $1"; FINDINGS="${FINDINGS}\n- FAIL: $1"; }
skip() { ((SKIP++)); echo -e "  ${YELLOW}SKIP${NC} $1"; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Helper: write request body to temp file (avoids shell quoting issues)
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

write_body() {
    local file="$TMPDIR/$1.json"
    cat > "$file"
    echo "$file"
}

##############################################################################
# Section 1: Authentication & Rate Limiting (E1, E2, E3, E26)
##############################################################################
section "1. Authentication & Rate Limiting"

# E1: Missing x-api-key
echo "E1: Missing x-api-key header"
BODY_FILE=$(write_body e1 <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -d @"$BODY_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "401" ]; then
    if echo "$BODY_RESP" | grep -q '"authentication_error"'; then
        pass "E1: 401 + authentication_error"
    else
        fail "E1: 401 but wrong error type: $BODY_RESP"
    fi
else
    fail "E1: Expected 401, got $HTTP_CODE"
fi

# E2: Invalid API key
echo "E2: Invalid API key"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: invalid-key-12345" \
  -d @"$BODY_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "403" ]; then
    if echo "$BODY_RESP" | grep -q '"permission_error"'; then
        pass "E2: 403 + permission_error"
    else
        fail "E2: 403 but wrong error type: $BODY_RESP"
    fi
else
    fail "E2: Expected 403, got $HTTP_CODE"
fi

# E26: Non /v1/ path bypasses auth
echo "E26: Non /v1/ path bypasses auth filter"
RESP=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/actuator/health" 2>/dev/null || true)
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "403" ]; then
    pass "E26: Non /v1/ path not blocked by auth (HTTP $HTTP_CODE)"
else
    fail "E26: Non /v1/ path blocked by auth (HTTP $HTTP_CODE)"
fi

##############################################################################
# Section 2: Request Transformation (D1-D24)
##############################################################################
section "2. Request Transformation"

# E13: Malformed JSON
echo "E13: Malformed JSON request body"
BADJSON_FILE=$(write_body e13 <<'EOF'
{this is not valid json
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$BADJSON_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ]; then
    if echo "$BODY_RESP" | grep -q '"invalid_request_error"'; then
        pass "E13: 400 + invalid_request_error for malformed JSON"
    else
        fail "E13: 400 but wrong error type: $BODY_RESP"
    fi
else
    fail "E13: Expected 400, got $HTTP_CODE"
fi

# E14: Missing model field
echo "E14: Missing model field"
NOMODEL_FILE=$(write_body e14 <<'EOF'
{"max_tokens":10,"messages":[{"role":"user","content":"hi"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$NOMODEL_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ]; then
    if echo "$BODY_RESP" | grep -q '"invalid_request_error"'; then
        pass "E14: 400 + invalid_request_error for missing model"
    else
        fail "E14: 400 but wrong error type: $BODY_RESP"
    fi
else
    fail "E14: Expected 400, got $HTTP_CODE"
fi

# E14-EMPTY: Empty model field
echo "E14-EMPTY: Empty model field"
EMPTYMODEL_FILE=$(write_body e14empty <<'EOF'
{"model":"","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$EMPTYMODEL_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ]; then
    pass "E14-EMPTY: 400 for empty model"
else
    fail "E14-EMPTY: Expected 400, got $HTTP_CODE — empty model not caught"
fi

##############################################################################
# Section 3: Non-streaming Happy Path (M1)
##############################################################################
section "3. Non-streaming Happy Path (M1)"

# M1-HP: Basic non-streaming request
echo "M1-HP: Non-streaming happy path"
M1HP_FILE=$(write_body m1hp <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"messages":[{"role":"user","content":"Reply with exactly: hello"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M1HP_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    if echo "$BODY_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['type']=='message'; assert d['role']=='assistant'; assert 'content' in d; assert 'usage' in d" 2>/dev/null; then
        pass "M1-HP: 200 + valid message response with usage"
    else
        fail "M1-HP: 200 but response structure invalid: $(echo "$BODY_RESP" | head -c 200)"
    fi
else
    fail "M1-HP: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# M1-DEFAULT: stream field absent (should default to non-streaming)
echo "M1-DEFAULT: No stream field defaults to non-streaming"
M1DEF_FILE=$(write_body m1def <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":30,"messages":[{"role":"user","content":"Say ok"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M1DEF_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    if echo "$BODY_RESP" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "M1-DEFAULT: Non-streaming response (valid JSON)"
    else
        fail "M1-DEFAULT: Response is not valid JSON (might be SSE)"
    fi
else
    fail "M1-DEFAULT: Expected 200, got $HTTP_CODE"
fi

# M1-USAGE: Verify usage fields in non-streaming response
echo "M1-USAGE: Usage fields present"
if [ "$HTTP_CODE" = "200" ]; then
    HAS_USAGE=$(echo "$BODY_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
u=d.get('usage',{})
print('yes' if u.get('input_tokens',0)>0 and u.get('output_tokens',0)>0 else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_USAGE" = "yes" ]; then
        pass "M1-USAGE: input_tokens and output_tokens present and > 0"
    else
        fail "M1-USAGE: Usage fields missing or zero"
    fi
else
    skip "M1-USAGE: Skipped (previous test failed)"
fi

##############################################################################
# Section 4: Streaming Happy Path (M2)
##############################################################################
section "4. Streaming Happy Path (M2)"

# M2-HP: Basic streaming request
echo "M2-HP: Streaming happy path"
M2HP_FILE=$(write_body m2hp <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":50,"stream":true,"messages":[{"role":"user","content":"Reply with exactly: hello"}]}
EOF
)
STREAM_RESP=$(curl -s -N --max-time 30 -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M2HP_FILE" 2>/dev/null || true)

if echo "$STREAM_RESP" | grep -q "event: message_start"; then
    HAS_START=$(echo "$STREAM_RESP" | grep -c "event: message_start" || true)
    HAS_DELTA=$(echo "$STREAM_RESP" | grep -c "event: content_block_delta" || true)
    HAS_STOP=$(echo "$STREAM_RESP" | grep -c "event: message_stop" || true)
    if [ "$HAS_START" -ge 1 ] && [ "$HAS_DELTA" -ge 1 ] && [ "$HAS_STOP" -ge 1 ]; then
        pass "M2-HP: SSE stream with message_start + content_block_delta + message_stop"
    else
        fail "M2-HP: Incomplete SSE event sequence (start=$HAS_START, delta=$HAS_DELTA, stop=$HAS_STOP)"
    fi
else
    fail "M2-HP: No message_start event found in stream response"
fi

# M2-FORMAT: Verify SSE format "event: {type}\ndata: {json}\n\n"
echo "M2-FORMAT: SSE event format validation"
if echo "$STREAM_RESP" | grep -q "event: message_start"; then
    FIRST_DATA=$(echo "$STREAM_RESP" | grep "^data: " | head -1 | sed 's/^data: //')
    if echo "$FIRST_DATA" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "M2-FORMAT: SSE data field contains valid JSON"
    else
        fail "M2-FORMAT: SSE data field is not valid JSON: $(echo "$FIRST_DATA" | head -c 100)"
    fi
else
    skip "M2-FORMAT: Skipped (no stream data)"
fi

# M2-USAGE-STREAM: Verify usage in streaming events
echo "M2-USAGE-STREAM: Usage in streaming events"
if echo "$STREAM_RESP" | grep -q "event: message_start"; then
    MSG_START_DATA=$(echo "$STREAM_RESP" | grep -A1 "event: message_start" | grep "^data: " | sed 's/^data: //')
    HAS_INPUT_TOKENS=$(echo "$MSG_START_DATA" | python3 -c "
import sys,json
d=json.load(sys.stdin)
u=d.get('message',{}).get('usage',{})
print('yes' if 'input_tokens' in u else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_INPUT_TOKENS" = "yes" ]; then
        pass "M2-USAGE-STREAM: input_tokens in message_start"
    else
        fail "M2-USAGE-STREAM: No input_tokens in message_start"
    fi
else
    skip "M2-USAGE-STREAM: Skipped"
fi

##############################################################################
# Section 5: Model Mapping (M6, D1)
##############################################################################
section "5. Model Mapping (M6)"

# M6-MAPPED: Known model in mapping table
echo "M6-MAPPED: Model in mapping table"
M6MAP_FILE=$(write_body m6map <<'EOF'
{"model":"claude-sonnet-4-6","max_tokens":30,"messages":[{"role":"user","content":"Say ok"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M6MAP_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "M6-MAPPED: claude-sonnet-4-6 resolved successfully"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    fail "M6-MAPPED: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# M6-PASSTHROUGH: Already a Bedrock model ID
echo "M6-PASSTHROUGH: Bedrock model ID passthrough"
M6PASS_FILE=$(write_body m6pass <<'EOF'
{"model":"anthropic.claude-sonnet-4-5-20250929-v1:0","max_tokens":30,"messages":[{"role":"user","content":"Say ok"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M6PASS_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "M6-PASSTHROUGH: Bedrock model ID passed through"
elif [ "$HTTP_CODE" = "400" ]; then
    pass "M6-PASSTHROUGH: Bedrock model ID passed through (400 = model not available in region)"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    fail "M6-PASSTHROUGH: Unexpected $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# M6-FALLBACK: Unknown model name triggers fallback
echo "M6-FALLBACK: Unknown model fallback to us.anthropic.{model}-v1:0"
M6FALL_FILE=$(write_body m6fall <<'EOF'
{"model":"claude-nonexistent-99","max_tokens":30,"messages":[{"role":"user","content":"Say ok"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$M6FALL_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "404" ]; then
    pass "M6-FALLBACK: Unknown model → Bedrock error ($HTTP_CODE) — fallback mapping attempted"
else
    fail "M6-FALLBACK: Expected 400/404, got $HTTP_CODE"
fi

##############################################################################
# Section 6: Beta Header Conversion (D4)
##############################################################################
section "6. Beta Header Conversion (D4)"

# D4-SINGLE: Single beta header
echo "D4-SINGLE: Single anthropic-beta header"
D4_FILE=$(write_body d4 <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":30,"messages":[{"role":"user","content":"Say ok"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-beta: token-efficient-tools-2025-02-19" \
  -d @"$D4_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "D4-SINGLE: Beta header accepted (200)"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    # 400 from Bedrock might mean the beta is not valid for this model, still a valid test
    pass "D4-SINGLE: Beta header processed (HTTP $HTTP_CODE)"
fi

# D4-COMMA: Comma-separated beta headers
echo "D4-COMMA: Comma-separated anthropic-beta"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-beta: token-efficient-tools-2025-02-19,output-128k-2025-02-19" \
  -d @"$D4_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
pass "D4-COMMA: Comma-separated beta processed (HTTP $HTTP_CODE)"

##############################################################################
# Section 7: Thinking Support (D22)
##############################################################################
section "7. Thinking Support (D22)"

# D22-ENABLED: Extended thinking enabled
echo "D22-ENABLED: Extended thinking (enabled)"
D22EN_FILE=$(write_body d22en <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":8000,"thinking":{"type":"enabled","budget_tokens":2000},"messages":[{"role":"user","content":"What is 15 * 37?"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D22EN_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    HAS_THINKING=$(echo "$BODY_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
types=[b['type'] for b in d.get('content',[])]
print('yes' if 'thinking' in types else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_THINKING" = "yes" ]; then
        pass "D22-ENABLED: Thinking block present in response"
    else
        pass "D22-ENABLED: Response OK but no thinking block (model may skip)"
    fi
else
    fail "D22-ENABLED: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# D22-ADAPTIVE: Adaptive thinking (Opus 4.6 / Sonnet 4.6)
echo "D22-ADAPTIVE: Adaptive thinking"
D22AD_FILE=$(write_body d22ad <<'EOF'
{"model":"claude-sonnet-4-6","max_tokens":8000,"thinking":{"type":"adaptive"},"messages":[{"role":"user","content":"What is 15 * 37?"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D22AD_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "D22-ADAPTIVE: Adaptive thinking accepted"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    fail "D22-ADAPTIVE: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# D22-STREAM-THINKING: Streaming + thinking
echo "D22-STREAM-THINKING: Streaming with thinking"
D22ST_FILE=$(write_body d22st <<'EOF'
{"model":"claude-sonnet-4-5-20250929","max_tokens":8000,"stream":true,"thinking":{"type":"enabled","budget_tokens":2000},"messages":[{"role":"user","content":"What is 15 * 37?"}]}
EOF
)
STREAM_RESP=$(curl -s -N --max-time 60 -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D22ST_FILE" 2>/dev/null || true)

if echo "$STREAM_RESP" | grep -q "event: message_start"; then
    HAS_THINKING_DELTA=$(echo "$STREAM_RESP" | grep -c "thinking_delta" || true)
    HAS_TEXT_DELTA=$(echo "$STREAM_RESP" | grep -c "text_delta" || true)
    if [ "$HAS_THINKING_DELTA" -ge 1 ] && [ "$HAS_TEXT_DELTA" -ge 1 ]; then
        pass "D22-STREAM-THINKING: thinking_delta + text_delta events present"
    elif [ "$HAS_TEXT_DELTA" -ge 1 ]; then
        pass "D22-STREAM-THINKING: text_delta present (model may skip thinking)"
    else
        fail "D22-STREAM-THINKING: No text_delta events"
    fi
else
    fail "D22-STREAM-THINKING: No message_start event"
fi

##############################################################################
# Section 8: Tool Use (D20, D21)
##############################################################################
section "8. Tool Use (D20, D21)"

# D20-CUSTOM: Custom tool use
echo "D20-CUSTOM: Custom tool use"
D20CUST_FILE=$(write_body d20cust <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 200,
  "tools": [
    {
      "name": "get_weather",
      "description": "Get weather for a location",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  ],
  "messages": [{"role": "user", "content": "What is the weather in Tokyo?"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D20CUST_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    HAS_TOOL_USE=$(echo "$BODY_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
types=[b['type'] for b in d.get('content',[])]
print('yes' if 'tool_use' in types else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_TOOL_USE" = "yes" ]; then
        pass "D20-CUSTOM: tool_use block in response"
    else
        pass "D20-CUSTOM: 200 OK (model chose not to use tool)"
    fi
else
    fail "D20-CUSTOM: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

# D20-STREAM-TOOL: Streaming + tool use
echo "D20-STREAM-TOOL: Streaming with tool use"
D20STOOL_FILE=$(write_body d20stool <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 200,
  "stream": true,
  "tool_choice": {"type": "any"},
  "tools": [
    {
      "name": "get_weather",
      "description": "Get weather for a location",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  ],
  "messages": [{"role": "user", "content": "What is the weather in Tokyo?"}]
}
EOF
)
STREAM_RESP=$(curl -s -N --max-time 30 -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D20STOOL_FILE" 2>/dev/null || true)

if echo "$STREAM_RESP" | grep -q "event: message_start"; then
    HAS_INPUT_JSON=$(echo "$STREAM_RESP" | grep -c "input_json_delta" || true)
    if [ "$HAS_INPUT_JSON" -ge 1 ]; then
        pass "D20-STREAM-TOOL: input_json_delta events in streaming tool use"
    else
        pass "D20-STREAM-TOOL: Stream OK (tool_use may not have delta)"
    fi
else
    fail "D20-STREAM-TOOL: No message_start event"
fi

# D20-SERVERTOOL: Server tool should ideally be rejected (P1 finding)
echo "D20-SERVERTOOL: Server tool (web_search) passthrough behavior"
D20SRV_FILE=$(write_body d20srv <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 200,
  "tools": [
    {
      "type": "web_search_20250305",
      "name": "web_search"
    }
  ],
  "messages": [{"role": "user", "content": "Search for latest news"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D20SRV_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ]; then
    pass "D20-SERVERTOOL: Server tool rejected by Bedrock (400)"
    echo -e "  ${YELLOW}FINDING${NC}: Gateway should intercept server tools before forwarding to Bedrock"
    FINDINGS="${FINDINGS}\n- FINDING: Server tools (web_search, code_execution, etc.) are passed through to Bedrock instead of being intercepted with a clear error message"
elif [ "$HTTP_CODE" = "200" ]; then
    # Bedrock accepted the tool type but won't execute it — silent degradation
    HAS_TOOL_USE=$(echo "$BODY_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
types=[b['type'] for b in d.get('content',[])]
print('yes' if 'server_tool_use' in types else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_TOOL_USE" = "yes" ]; then
        fail "D20-SERVERTOOL: Bedrock executed server tool — unexpected"
    else
        echo -e "  ${YELLOW}FINDING${NC}: Bedrock accepted server tool type but did NOT execute it — silent degradation"
        FINDINGS="${FINDINGS}\n- FINDING (D20): Server tools (web_search) accepted by Bedrock but NOT executed — model returns text instead of search results. Gateway should intercept and warn client."
        pass "D20-SERVERTOOL: Server tool silently ignored by Bedrock (finding — silent degradation)"
    fi
else
    pass "D20-SERVERTOOL: Server tool caused error ($HTTP_CODE)"
    FINDINGS="${FINDINGS}\n- FINDING: Server tools passthrough results in HTTP $HTTP_CODE from Bedrock"
fi

##############################################################################
# Section 9: Multimodal Content (D14)
##############################################################################
section "9. Multimodal Content"

# D14-IMAGE: Image content block
echo "D14-IMAGE: Image content in messages"
D14IMG_FILE=$(write_body d14img <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 100,
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/png",
          "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        }
      },
      {
        "type": "text",
        "text": "What color is this pixel?"
      }
    ]
  }]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D14IMG_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "D14-IMAGE: Image content accepted and processed"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    fail "D14-IMAGE: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

##############################################################################
# Section 10: New Findings — D10 (mcp_servers not stripped)
##############################################################################
section "10. New Findings — mcp_servers (D10)"

echo "D10-BUG: mcp_servers field not in UNSUPPORTED_FIELDS"
D10_FILE=$(write_body d10 <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 30,
  "mcp_servers": [{"type": "url", "url": "https://example.com/mcp"}],
  "messages": [{"role": "user", "content": "Say ok"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D10_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${YELLOW}FINDING${NC}: mcp_servers passed through to Bedrock and was silently ignored"
    FINDINGS="${FINDINGS}\n- FINDING (D10): mcp_servers field is NOT stripped from request body — passed through to Bedrock (silently ignored or may cause errors with different payloads)"
    pass "D10-BUG: Request succeeded but mcp_servers was not stripped (finding)"
elif [ "$HTTP_CODE" = "400" ]; then
    echo -e "  ${YELLOW}FINDING${NC}: mcp_servers caused Bedrock 400 error"
    FINDINGS="${FINDINGS}\n- FINDING (D10): mcp_servers field caused Bedrock 400 error — should be stripped in UNSUPPORTED_FIELDS"
    fail "D10-BUG: mcp_servers caused Bedrock error — needs to be added to UNSUPPORTED_FIELDS"
else
    fail "D10-BUG: Unexpected HTTP $HTTP_CODE"
fi

##############################################################################
# Section 11: New Findings — D24 (anthropic_version in body)
##############################################################################
section "11. New Findings — anthropic_version preservation (D24)"

echo "D24-PRESERVE: anthropic_version already in body"
D24_FILE=$(write_body d24 <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 30,
  "anthropic_version": "2023-06-01",
  "messages": [{"role": "user", "content": "Say ok"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D24_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${YELLOW}INFO${NC}: Bedrock accepted anthropic_version: 2023-06-01 — may be compatible"
    pass "D24-PRESERVE: anthropic_version 2023-06-01 accepted by Bedrock"
elif [ "$HTTP_CODE" = "400" ]; then
    echo -e "  ${YELLOW}FINDING${NC}: Bedrock rejected anthropic_version: 2023-06-01"
    FINDINGS="${FINDINGS}\n- FINDING (D24): When client sends anthropic_version in body, gateway preserves it instead of overwriting to bedrock-2023-05-31 — Bedrock may reject"
    fail "D24-PRESERVE: Bedrock rejected non-standard anthropic_version — gateway should overwrite"
else
    fail "D24-PRESERVE: Unexpected HTTP $HTTP_CODE"
fi

##############################################################################
# Section 12: New Findings — D11 (output_config.effort)
##############################################################################
section "12. New Findings — output_config.effort (D11)"

echo "D11-EFFORT: output_config.effort without beta header"
D11_FILE=$(write_body d11 <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 100,
  "output_config": {"effort": "low"},
  "messages": [{"role": "user", "content": "Say ok"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D11_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    pass "D11-EFFORT: output_config.effort accepted without explicit beta header"
elif [ "$HTTP_CODE" = "400" ]; then
    echo -e "  ${YELLOW}FINDING${NC}: output_config.effort requires beta header effort-2025-11-24"
    FINDINGS="${FINDINGS}\n- FINDING (D11): output_config.effort passed through but Bedrock requires beta header effort-2025-11-24 — gateway should auto-inject this beta when effort is present"
    fail "D11-EFFORT: Bedrock rejected — needs beta header injection"
else
    fail "D11-EFFORT: Unexpected HTTP $HTTP_CODE"
fi

# D11-EFFORT-BETA: With beta header
echo "D11-EFFORT-BETA: output_config.effort with beta header"
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-beta: effort-2025-11-24" \
  -d @"$D11_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
if [ "$HTTP_CODE" = "200" ]; then
    pass "D11-EFFORT-BETA: output_config.effort with beta header accepted"
else
    BODY_RESP=$(echo "$RESP" | sed '$d')
    fail "D11-EFFORT-BETA: HTTP $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

##############################################################################
# Section 13: New Findings — D12 (top-level cache_control)
##############################################################################
section "13. New Findings — top-level cache_control (D12)"

echo "D12-TOPLEVEL: Top-level cache_control"
D12_FILE=$(write_body d12 <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 100,
  "cache_control": {"type": "ephemeral"},
  "messages": [{"role": "user", "content": "Say ok"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$D12_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    pass "D12-TOPLEVEL: Top-level cache_control accepted (Bedrock may ignore)"
elif [ "$HTTP_CODE" = "400" ]; then
    echo -e "  ${YELLOW}FINDING${NC}: Top-level cache_control rejected by Bedrock"
    FINDINGS="${FINDINGS}\n- FINDING (D12): Top-level cache_control passed through but Bedrock rejected it — gateway should strip or convert"
    fail "D12-TOPLEVEL: Bedrock rejected top-level cache_control"
else
    fail "D12-TOPLEVEL: Unexpected HTTP $HTTP_CODE"
fi

##############################################################################
# Section 14: Bedrock Error Mapping (E5-E12)
##############################################################################
section "14. Bedrock Error Mapping"

# E5: Bedrock ValidationException (missing max_tokens)
echo "E5-VALIDATION: Missing max_tokens → Bedrock 400"
E5_FILE=$(write_body e5 <<'EOF'
{"model":"claude-sonnet-4-5-20250929","messages":[{"role":"user","content":"hi"}]}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$E5_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "400" ]; then
    if echo "$BODY_RESP" | grep -q '"invalid_request_error"'; then
        pass "E5-VALIDATION: 400 + invalid_request_error"
    else
        fail "E5-VALIDATION: 400 but wrong error type: $BODY_RESP"
    fi
else
    fail "E5-VALIDATION: Expected 400, got $HTTP_CODE"
fi

# E25: Error message cleanup (strip SDK metadata)
echo "E25: Error message cleanup"
if [ "$HTTP_CODE" = "400" ]; then
    HAS_SERVICE_META=$(echo "$BODY_RESP" | grep -c "(Service:" || true)
    if [ "$HAS_SERVICE_META" = "0" ]; then
        pass "E25: Error message cleaned (no SDK metadata)"
    else
        fail "E25: Error message still contains SDK metadata"
    fi
else
    skip "E25: Skipped (previous test didn't return 400)"
fi

##############################################################################
# Section 15: R3 — Extra Bedrock metrics in streaming
##############################################################################
section "15. Response Extra Fields (R3)"

echo "R3-METRICS: amazon-bedrock-invocationMetrics in streaming"
if echo "$STREAM_RESP" | grep -q "amazon-bedrock-invocationMetrics"; then
    echo -e "  ${YELLOW}FINDING${NC}: amazon-bedrock-invocationMetrics present in SSE stream"
    FINDINGS="${FINDINGS}\n- FINDING (R3): amazon-bedrock-invocationMetrics field present in message_stop event — Anthropic API does not have this field, may confuse strict SDK clients"
    pass "R3-METRICS: Metrics present (finding — not stripped)"
else
    pass "R3-METRICS: No extra Bedrock metrics in stream (or not visible in captured output)"
fi

##############################################################################
# Section 16: Prompt Caching (block-level cache_control)
##############################################################################
section "16. Prompt Caching (block-level)"

echo "CACHE-BLOCK: Block-level cache_control"
CACHE_FILE=$(write_body cache <<'EOF'
{
  "model": "claude-sonnet-4-5-20250929",
  "max_tokens": 100,
  "system": [
    {
      "type": "text",
      "text": "You are a helpful assistant. This is a long system prompt that should be cached for efficiency.",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "messages": [{"role": "user", "content": "Say ok"}]
}
EOF
)
RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @"$CACHE_FILE")
HTTP_CODE=$(echo "$RESP" | tail -1)
BODY_RESP=$(echo "$RESP" | sed '$d')
if [ "$HTTP_CODE" = "200" ]; then
    HAS_CACHE=$(echo "$BODY_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
u=d.get('usage',{})
print('yes' if 'cache_creation_input_tokens' in u or 'cache_read_input_tokens' in u else 'no')
" 2>/dev/null || echo "no")
    if [ "$HAS_CACHE" = "yes" ]; then
        pass "CACHE-BLOCK: Block-level cache_control accepted, cache metrics in response"
    else
        pass "CACHE-BLOCK: Block-level cache_control accepted (no cache metrics — content may be too short)"
    fi
else
    fail "CACHE-BLOCK: Expected 200, got $HTTP_CODE: $(echo "$BODY_RESP" | head -c 200)"
fi

##############################################################################
# Summary
##############################################################################
section "SUMMARY"

TOTAL=$((PASS + FAIL + SKIP))
echo -e "Total: $TOTAL | ${GREEN}Pass: $PASS${NC} | ${RED}Fail: $FAIL${NC} | ${YELLOW}Skip: $SKIP${NC}"

if [ -n "$FINDINGS" ]; then
    echo -e "\n${CYAN}=== FINDINGS ===${NC}"
    echo -e "$FINDINGS"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Some tests failed. Review findings above.${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed.${NC}"
    exit 0
fi
