#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    echo "Please install '$1' first, then rerun this script." >&2
    exit 1
  }
}

transform_wallstreetcn_hot() {
  jq -c '
    [
      .data.day_items[]?
      | select(.title and .uri)
      | select(.title | contains("华尔街见闻早餐") | not)
      | select(.uri | contains("premium/articles") | not)
      | {
          title: .title,
          url: .uri
        }
    ]
  '
}

transform_sspai_hot() {
  jq -c '
    [
      .data[]?
      | select(.title and .id)
      | select(.title | contains("福利派") | not)
      | {
          title: .title,
          url: ("https://sspai.com/post/" + (.id | tostring)),
          summary: (.summary // "")
        }
    ]
  '
}

transform_longbridge_hot() {
  jq -c '
    [
      .data.events[]?
      | (.event // .) as $event
      | select($event.title and $event.id)
      | {
          title: $event.title,
          url: ("https://web.lbkrs.com/zh-CN/events/" + ($event.id | tostring) + "?channel=n" + ($event.id | tostring)),
          summary: ($event.overview // "")
        }
    ]
  '
}

build_longbridge_hot_payload() {
  local score_min="$1"
  local time_end
  local time_start

  time_end="$(date +%s)"
  time_start="$((time_end - 86400))"

  jq -cn \
    --argjson time_start "$time_start" \
    --argjson time_end "$time_end" \
    --argjson score_min "$score_min" \
    '{
      filter: {
        time_start: $time_start,
        time_end: $time_end,
        categories: ["ReportDate", "FinancialReport", "MacroDataUpdated", "MacroDataDate", "PostEvent"],
        score_min: $score_min,
        score_max: 10
      },
      option: {
        with_overview: true,
        with_summary: false,
        with_stocks: true,
        with_social: false,
        with_resources: true,
        with_news_posts: true,
        with_derivatives: true
      },
      sort: [
        { field: "issued_at", order: 2 },
        { field: "score", order: 2 }
      ],
      query: {
        size: 20,
        visited: []
      }
    }'
}

print_json() {
  local payload="$1"
  local COMPACT="${2:-1}"
  if [[ "$COMPACT" == "1" ]]; then
    printf '%s\n' "$payload" | jq -c .
  else
    printf '%s\n' "$payload" | jq .
  fi
}

build_payload() {
  local wallstreetcn_hot="$1"
  local sspai_hot="$2"
  local longbridge_hot="$3"

  jq -n \
    --argjson wallstreetcn_hot "$wallstreetcn_hot" \
    --argjson sspai_hot "$sspai_hot" \
    --argjson longbridge_hot "$longbridge_hot" \
    '
      {
        wallstreetcn_hot: $wallstreetcn_hot,
        sspai_hot: $sspai_hot,
        longbridge_hot: $longbridge_hot
      }
    '
}

filter_payload() {
  local payload="$1"
  local SOURCE="${2:-all}"
  case "$SOURCE" in
    all)
      printf '%s\n' "$payload"
      ;;
    wallstreetcn-hot)
      printf '%s\n' "$payload" | jq '{wallstreetcn_hot}'
      ;;
    sspai-hot)
      printf '%s\n' "$payload" | jq '{sspai_hot}'
      ;;
    longbridge-hot)
      printf '%s\n' "$payload" | jq '{longbridge_hot}'
      ;;
    *)
      echo "Unsupported source: $SOURCE" >&2
      exit 1
      ;;
  esac
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

ensure_state_file() {
  local READ_URLS_FILE="$1"
  mkdir -p "$(dirname "$READ_URLS_FILE")"
  touch "$READ_URLS_FILE"
}

filter_unread_items() {
  local items_json="$1"
  local READ_URLS_FILE="$2"
  local tmp_file
  tmp_file="$(mktemp)"

  printf '%s\n' "$items_json" | jq -c '.[]' | while IFS= read -r item; do
    local url
    url="$(printf '%s\n' "$item" | jq -r '.url')"
    if ! grep -Fqx "$url" "$READ_URLS_FILE"; then
      printf '%s\n' "$item"
    fi
  done > "$tmp_file"

  if [[ -s "$tmp_file" ]]; then
    jq -s '.' < "$tmp_file"
  else
    printf '[]\n'
  fi

  rm -f "$tmp_file"
}

mark_items_as_read() {
  local items_json="$1"
  local READ_URLS_FILE="$2"
  printf '%s\n' "$items_json" | jq -r '.[].url' | while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if ! grep -Fqx "$url" "$READ_URLS_FILE"; then
      printf '%s\n' "$url" >> "$READ_URLS_FILE"
    fi
  done
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

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --compact)
        COMPACT="1"
        shift
        ;;
      --pretty-print)
        COMPACT="0"
        shift
        ;;
      --help|-h)
        cat <<'EOF'
Usage: fetch_feed_test.sh [--compact|--pretty-print] [--help|-h]
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
  print_json "$test_output" "$COMPACT"
}

main "$@"
