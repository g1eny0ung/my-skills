#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
source "$SCRIPT_DIR/fetch_feed_common.sh"

ASSERTIONS_PASSED=0

# Writes to stderr because main captures run_self_test's stdout.
# Argument order: description, expected, actual — expected always comes first.
assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    return 0
  fi

  local caller_info
  caller_info="$(caller)"
  echo "FAIL: $description (at $caller_info)" >&2
  echo "  expected: $expected" >&2
  echo "  actual:   $actual" >&2
  exit 1
}

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

# Runs fetch_feed.sh in a subshell; every failure path here exits before any
# network access or state-file writes.
self_test_arg_validation() {
  local fetch_script="$SCRIPT_DIR/fetch_feed.sh"
  local status=0
  local err

  status=0
  err="$(bash "$fetch_script" --source 2>&1 >/dev/null)" || status=$?
  assert_eq "missing --source value exit code" "1" "$status"
  assert_eq "missing --source value message" "Missing value for --source" "${err%%$'\n'*}"

  status=0
  err="$(bash "$fetch_script" --timeout abc 2>&1 >/dev/null)" || status=$?
  assert_eq "invalid --timeout exit code" "1" "$status"
  assert_eq "invalid --timeout message" "Invalid --timeout value: must be a number" "${err%%$'\n'*}"

  status=0
  err="$(bash "$fetch_script" --longbridge-score-min abc 2>&1 >/dev/null)" || status=$?
  assert_eq "invalid --longbridge-score-min exit code" "1" "$status"
  assert_eq "invalid --longbridge-score-min message" "Invalid --longbridge-score-min value: must be a number" "${err%%$'\n'*}"

  status=0
  err="$(bash "$fetch_script" --longbridge-score-min 11 2>&1 >/dev/null)" || status=$?
  assert_eq "excessive --longbridge-score-min exit code" "1" "$status"
  assert_eq "excessive --longbridge-score-min message" "Invalid --longbridge-score-min value: must not exceed 10" "${err%%$'\n'*}"
}

run_self_test() {
  require_cmd jq

  local wallstreetcn_hot
  local sspai_hot
  local longbridge_hot
  local payload
  local state_file
  local longbridge_payload
  local partial_state

  state_file="$(mktemp)"
  READ_URLS_FILE="$state_file"
  ensure_state_file "$READ_URLS_FILE"

  wallstreetcn_hot="$(self_test_hot_fixture | transform_wallstreetcn_hot)"
  sspai_hot="$(self_test_sspai_fixture | transform_sspai_hot)"
  longbridge_hot="$(self_test_longbridge_fixture | transform_longbridge_hot)"

  assert_eq "transform_wallstreetcn_hot" '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' "$wallstreetcn_hot"
  assert_eq "transform_sspai_hot" '[{"title":"SSPAI article","url":"https://sspai.com/post/789","summary":"SSPAI summary"}]' "$sspai_hot"
  assert_eq "transform_longbridge_hot" '[{"title":"Longbridge event","url":"https://web.lbkrs.com/zh-CN/events/3125600?channel=n3125600","summary":"Longbridge overview"}]' "$longbridge_hot"

  # Test build_longbridge_hot_payload with default score_min
  longbridge_payload="$(build_longbridge_hot_payload 6)"
  assert_eq "default score_min" "6" "$(jq -r '.filter.score_min' <<<"$longbridge_payload")"
  assert_eq "default score_max" "10" "$(jq -r '.filter.score_max' <<<"$longbridge_payload")"

  # Test build_longbridge_hot_payload with custom score_min
  longbridge_payload="$(build_longbridge_hot_payload 5)"
  assert_eq "custom score_min" "5" "$(jq -r '.filter.score_min' <<<"$longbridge_payload")"

  # Test build_longbridge_hot_payload with custom score_min as float
  longbridge_payload="$(build_longbridge_hot_payload 7.5)"
  assert_eq "float score_min" "7.5" "$(jq -r '.filter.score_min' <<<"$longbridge_payload")"

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot" "$READ_URLS_FILE")"
  sspai_hot="$(filter_unread_items "$sspai_hot" "$READ_URLS_FILE")"
  longbridge_hot="$(filter_unread_items "$longbridge_hot" "$READ_URLS_FILE")"
  mark_items_as_read "$wallstreetcn_hot" "$READ_URLS_FILE"
  mark_items_as_read "$sspai_hot" "$READ_URLS_FILE"
  mark_items_as_read "$longbridge_hot" "$READ_URLS_FILE"

  # Items marked above must be dropped by a subsequent filter pass.
  assert_eq "re-filter drops marked wallstreetcn items" "[]" "$(filter_unread_items "$wallstreetcn_hot" "$state_file")"
  assert_eq "re-filter drops marked sspai items" "[]" "$(filter_unread_items "$sspai_hot" "$state_file")"
  assert_eq "re-filter drops marked longbridge items" "[]" "$(filter_unread_items "$longbridge_hot" "$state_file")"

  # Partial filtering: a recorded URL is dropped while unread URLs survive.
  partial_state="$(mktemp)"
  printf '%s\n' "https://sspai.com/post/789" >> "$partial_state"
  assert_eq "filter drops recorded sspai item" "[]" "$(filter_unread_items "$sspai_hot" "$partial_state")"
  assert_eq "filter keeps unrecorded wallstreetcn item" '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' "$(filter_unread_items "$wallstreetcn_hot" "$partial_state" | jq -c .)"
  rm -f "$partial_state"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot")"
  assert_eq "payload keys" '["longbridge_hot","sspai_hot","wallstreetcn_hot"]' "$(jq -c 'keys' <<<"$payload")"
  assert_eq "payload item counts" '[1,1,1]' "$(jq -c '[(.wallstreetcn_hot | length), (.sspai_hot | length), (.longbridge_hot | length)]' <<<"$payload")"
  assert_eq "filter_payload keeps only wallstreetcn" '["wallstreetcn_hot"]' "$(filter_payload "$payload" wallstreetcn-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only sspai" '["sspai_hot"]' "$(filter_payload "$payload" sspai-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only longbridge" '["longbridge_hot"]' "$(filter_payload "$payload" longbridge-hot | jq -c 'keys')"

  filter_payload "$payload" >/dev/null

  rm -f "$state_file"

  self_test_arg_validation

  echo "OK: $ASSERTIONS_PASSED assertions passed."
}

main() {
  local test_output
  test_output="$(run_self_test)"
  printf '%s\n' "$test_output"
}

main
