#!/bin/bash
# Test multimodal (image input)
# Using a tiny 1x1 red pixel PNG as base64
IMAGE_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

curl -s http://localhost:8080/v1/messages \
  -H "x-api-key: gw-test-key-001" \
  -H "content-type: application/json" \
  -d "{
    \"model\": \"claude-haiku-4-5-20251001\",
    \"max_tokens\": 200,
    \"messages\": [
        {
            \"role\": \"user\",
            \"content\": [
                {
                    \"type\": \"image\",
                    \"source\": {
                        \"type\": \"base64\",
                        \"media_type\": \"image/png\",
                        \"data\": \"${IMAGE_B64}\"
                    }
                },
                {
                    \"type\": \"text\",
                    \"text\": \"What color is this image?\"
                }
            ]
        }
    ]
  }" | python3 -m json.tool
