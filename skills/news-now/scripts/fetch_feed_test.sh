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

# Two node feeds concatenated on stdin; covers cross-feed dedupe and date sort.
self_test_v2ex_fixture() {
  cat <<'EOF'
{"title":"分享创造","items":[{"id":"1","title":"Newer post","url":"https://www.v2ex.com/t/2","date_published":"2026-09-13T14:53:02+00:00"},{"id":"2","title":"Older post","url":"https://www.v2ex.com/t/1","date_published":"2026-09-13T08:00:00+00:00"},{"id":"4","title":"","url":"https://www.v2ex.com/t/4","date_published":"2026-09-13T16:00:00+00:00"}]}
{"title":"程序员","items":[{"id":"3","title":"Dup post","url":"https://www.v2ex.com/t/3","date_published":"2026-09-13T12:00:00+00:00"},{"id":"3","title":"Dup post","url":"https://www.v2ex.com/t/3","date_published":"2026-09-13T12:00:00+00:00"}]}
EOF
}

self_test_hackernews_fixture() {
  cat <<'EOF'
{"hits":[{"objectID":"111","title":"Story with link","url":"https://example.com/a","points":100,"num_comments":50},{"objectID":"222","title":"Ask HN: no link","url":null,"points":1,"num_comments":0},{"objectID":"333","title":null,"url":null}]}
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
  local v2ex_hot
  local hackernews_hot
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
  v2ex_hot="$(self_test_v2ex_fixture | transform_v2ex_hot)"
  hackernews_hot="$(self_test_hackernews_fixture | transform_hackernews_hot)"

  assert_eq "transform_wallstreetcn_hot" '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' "$wallstreetcn_hot"
  assert_eq "transform_sspai_hot" '[{"title":"SSPAI article","url":"https://sspai.com/post/789","summary":"SSPAI summary"}]' "$sspai_hot"
  assert_eq "transform_longbridge_hot" '[{"title":"Longbridge event","url":"https://web.lbkrs.com/zh-CN/events/3125600?channel=n3125600","summary":"Longbridge overview"}]' "$longbridge_hot"
  assert_eq "transform_v2ex_hot merges, dedupes, sorts newest first" '[{"title":"Newer post","url":"https://www.v2ex.com/t/2"},{"title":"Dup post","url":"https://www.v2ex.com/t/3"},{"title":"Older post","url":"https://www.v2ex.com/t/1"}]' "$v2ex_hot"
  assert_eq "transform_hackernews_hot falls back to discussion url" '[{"title":"Story with link","url":"https://example.com/a"},{"title":"Ask HN: no link","url":"https://news.ycombinator.com/item?id=222"}]' "$hackernews_hot"

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
  v2ex_hot="$(filter_unread_items "$v2ex_hot" "$READ_URLS_FILE")"
  hackernews_hot="$(filter_unread_items "$hackernews_hot" "$READ_URLS_FILE")"
  mark_items_as_read "$wallstreetcn_hot" "$READ_URLS_FILE"
  mark_items_as_read "$sspai_hot" "$READ_URLS_FILE"
  mark_items_as_read "$longbridge_hot" "$READ_URLS_FILE"
  mark_items_as_read "$v2ex_hot" "$READ_URLS_FILE"
  mark_items_as_read "$hackernews_hot" "$READ_URLS_FILE"

  # Items marked above must be dropped by a subsequent filter pass.
  assert_eq "re-filter drops marked wallstreetcn items" "[]" "$(filter_unread_items "$wallstreetcn_hot" "$state_file")"
  assert_eq "re-filter drops marked sspai items" "[]" "$(filter_unread_items "$sspai_hot" "$state_file")"
  assert_eq "re-filter drops marked longbridge items" "[]" "$(filter_unread_items "$longbridge_hot" "$state_file")"
  assert_eq "re-filter drops marked v2ex items" "[]" "$(filter_unread_items "$v2ex_hot" "$state_file")"
  assert_eq "re-filter drops marked hackernews items" "[]" "$(filter_unread_items "$hackernews_hot" "$state_file")"

  # Partial filtering: a recorded URL is dropped while unread URLs survive.
  partial_state="$(mktemp)"
  printf '%s\n' "https://sspai.com/post/789" >> "$partial_state"
  assert_eq "filter drops recorded sspai item" "[]" "$(filter_unread_items "$sspai_hot" "$partial_state")"
  assert_eq "filter keeps unrecorded wallstreetcn item" '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' "$(filter_unread_items "$wallstreetcn_hot" "$partial_state" | jq -c .)"
  rm -f "$partial_state"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot" "$v2ex_hot" "$hackernews_hot")"
  assert_eq "payload keys" '["hackernews_hot","longbridge_hot","sspai_hot","v2ex_hot","wallstreetcn_hot"]' "$(jq -c 'keys' <<<"$payload")"
  assert_eq "payload item counts" '[1,1,1,3,2]' "$(jq -c '[(.wallstreetcn_hot | length), (.sspai_hot | length), (.longbridge_hot | length), (.v2ex_hot | length), (.hackernews_hot | length)]' <<<"$payload")"
  assert_eq "filter_payload keeps only wallstreetcn" '["wallstreetcn_hot"]' "$(filter_payload "$payload" wallstreetcn-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only sspai" '["sspai_hot"]' "$(filter_payload "$payload" sspai-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only longbridge" '["longbridge_hot"]' "$(filter_payload "$payload" longbridge-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only v2ex" '["v2ex_hot"]' "$(filter_payload "$payload" v2ex-hot | jq -c 'keys')"
  assert_eq "filter_payload keeps only hackernews" '["hackernews_hot"]' "$(filter_payload "$payload" hackernews-hot | jq -c 'keys')"

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
