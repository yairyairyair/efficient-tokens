#!/usr/bin/env bash

# dependencies:
# - jq
# - npx
# - @toon-format/cli

set -euo pipefail

input_payload="$(cat)"

# create a copy of the input_payload in the same directory for debugging
# echo "$input_payload" > ./input_payload.json

# tool_output usually arrives as a JSON-encoded string in hook payloads.
tool_output_obj="$(
  printf '%s' "$input_payload" | jq -cer '
    .tool_output as $t
    | if ($t == null) then empty
      elif ($t | type) == "string" then ($t | fromjson?)
      elif ($t | type) == "object" then $t
      else empty
      end
  ' 2>/dev/null || true
)"

if [[ -z "${tool_output_obj}" ]]; then
  exit 0
fi

# Find the first text content entry whose text is itself a JSON object string.
target_index="$(
  printf '%s' "$tool_output_obj" | jq -cer '
    if (.content | type) != "array" then empty
    else
      first(
        .content
        | to_entries[]
        | select(
            (.value.type == "text")
            and ((.value.text | type) == "string")
            and ((.value.text | fromjson? | type) == "object")
          )
      ).key
    end
  ' 2>/dev/null || true
)"

if [[ -z "${target_index}" ]]; then
  exit 0
fi

json_text="$(
  printf '%s' "$tool_output_obj" | jq -r --argjson idx "$target_index" '.content[$idx].text'
)"

# currently using @toon-format/cli to format the text, but we should use a more efficient token formatter
toon_text="$(printf '%s' "$json_text" | npx --yes @toon-format/cli 2>/dev/null || true)"

if [[ -z "${toon_text}" ]]; then
  exit 0
fi

updated_tool_output="$(
  printf '%s' "$tool_output_obj" | jq -c --argjson idx "$target_index" --arg toon "$toon_text" '
    .content[$idx].text = $toon
  '
)"

jq -cn --argjson updated "$updated_tool_output" '{ updated_mcp_tool_output: $updated }'
