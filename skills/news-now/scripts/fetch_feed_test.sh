#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
source "$SCRIPT_DIR/fetch_feed_common.sh"

self_test_hot_fixture() {
  cat <<'EOF'
{"data":{"day_items":[{"title":"Hot article","uri":"https://wallstreetcn.com/articles/123"},{"title":"Premium article","uri":"https://wallstreetcn.com/premium/articles/456?layout=wscn-layout"},{"title":"华尔街见闻早餐FM-Radio | 2026年4月10日","uri":"https://wallstreetcn.com/articles/999"}]}}
EOF
}

self_test_sspai_fixture() {
  cat <<'EOF'
{"data":[{"id":789,"title":"SSPAI article","summary":"SSPAI summary"},{"id":790,"title":"福利派 | 今日特惠","summary":"ignore me"}]}
EOF
}

self_test_longbridge_fixture() {
  cat <<'EOF'
{"data":{"events":[{"event":{"id":"3125600","title":"Longbridge event","overview":"Longbridge overview"}}]}}
EOF
}

run_self_test() {
  require_cmd bash
  require_cmd jq

  local wallstreetcn_hot
  local sspai_hot
  local longbridge_hot
  local payload
  local state_file
  local longbridge_payload

  state_file="$(mktemp)"
  READ_URLS_FILE="$state_file"
  ensure_state_file "$READ_URLS_FILE"

  wallstreetcn_hot="$(self_test_hot_fixture | transform_wallstreetcn_hot)"
  sspai_hot="$(self_test_sspai_fixture | transform_sspai_hot)"
  longbridge_hot="$(self_test_longbridge_fixture | transform_longbridge_hot)"

  [[ "$wallstreetcn_hot" == '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' ]] || exit 1
  [[ "$sspai_hot" == '[{"title":"SSPAI article","url":"https://sspai.com/post/789","summary":"SSPAI summary"}]' ]] || exit 1
  [[ "$longbridge_hot" == '[{"title":"Longbridge event","url":"https://web.lbkrs.com/zh-CN/events/3125600?channel=n3125600","summary":"Longbridge overview"}]' ]] || exit 1

  # Test build_longbridge_hot_payload with default score_min
  longbridge_payload="$(build_longbridge_hot_payload 6)"
  [[ $(jq -r '.filter.score_min' <<<"$longbridge_payload") == "6" ]] || exit 1
  [[ $(jq -r '.filter.score_max' <<<"$longbridge_payload") == "10" ]] || exit 1

  # Test build_longbridge_hot_payload with custom score_min
  longbridge_payload="$(build_longbridge_hot_payload 5)"
  [[ $(jq -r '.filter.score_min' <<<"$longbridge_payload") == "5" ]] || exit 1

  # Test build_longbridge_hot_payload with custom score_min as float
  longbridge_payload="$(build_longbridge_hot_payload 7.5)"
  [[ $(jq -r '.filter.score_min' <<<"$longbridge_payload") == "7.5" ]] || exit 1

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot" "$READ_URLS_FILE")"
  sspai_hot="$(filter_unread_items "$sspai_hot" "$READ_URLS_FILE")"
  longbridge_hot="$(filter_unread_items "$longbridge_hot" "$READ_URLS_FILE")"
  mark_items_as_read "$wallstreetcn_hot" "$READ_URLS_FILE"
  mark_items_as_read "$sspai_hot" "$READ_URLS_FILE"
  mark_items_as_read "$longbridge_hot" "$READ_URLS_FILE"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot")"
  filter_payload "$payload"

  rm -f "$state_file"
}

main() {
  local COMPACT="1"
  local OUTPUT_FORMAT="json"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compact)
        COMPACT="1"
        OUTPUT_FORMAT="json"
        shift
        ;;
      --pretty-print)
        COMPACT="0"
        OUTPUT_FORMAT="json"
        shift
        ;;
      --txt)
        OUTPUT_FORMAT="txt"
        shift
        ;;
      --help|-h)
        cat <<'EOF'
Usage: fetch_feed_test.sh [--compact|--pretty-print|--txt] [--help|-h]
EOF
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  local test_output
  test_output="$(run_self_test)"
  print_output "$test_output" "$OUTPUT_FORMAT" "$COMPACT"
}

main "$@"
