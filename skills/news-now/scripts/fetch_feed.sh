#!/usr/bin/env bash

set -euo pipefail

SOURCE="all"
TIMEOUT="15"
COMPACT="1"
SELF_TEST="0"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/data"
READ_URLS_FILE="$STATE_DIR/read_urls.txt"

WALLSTREETCN_HOT_URL="https://api-one-wscn.awtmt.com/apiv1/content/articles/hot?period=all"
SSPAI_HOT_URL="https://sspai.com/api/v1/article/hot/page/get"

usage() {
  cat <<'EOF'
Usage: fetch_feed.sh [--source all|wallstreetcn-hot|sspai-hot|longbridge-hot] [--timeout seconds] [--state-file path] [--pretty-print] [--self-test]
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    echo "Please install '$1' first, then rerun this script." >&2
    exit 1
  }
}

fetch_json() {
  local url="$1"
  curl -fsSL --max-time "$TIMEOUT" \
    -H "User-Agent: $USER_AGENT" \
    -H "Accept: application/json" \
    "$url"
}

fetch_json_post() {
  local url="$1"
  local payload="$2"
  curl -fsSL --max-time "$TIMEOUT" \
    -H "User-Agent: $USER_AGENT" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "$url"
}

transform_wallstreetcn_hot() {
  jq -c '
    [
      .data.day_items[]?
      | select(.title and .uri)
      | select(.title | contains("华尔街见闻早餐") | not)
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

build_sspai_url() {
  local created_at
  created_at="$(date +%s)"
  printf '%s?offset=0&limit=10&created_at=%s\n' "$SSPAI_HOT_URL" "$created_at"
}

build_longbridge_hot_payload() {
  local time_end
  local time_start

  time_end="$(date +%s)"
  time_start="$((time_end - 86400))"

  jq -cn \
    --argjson time_start "$time_start" \
    --argjson time_end "$time_end" \
    '{
      filter: {
        time_start: $time_start,
        time_end: $time_end,
        categories: ["ReportDate", "FinancialReport", "MacroDataUpdated", "MacroDataDate", "PostEvent"],
        score_min: 6,
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
{"data":{"day_items":[{"title":"Hot article","uri":"https://wallstreetcn.com/articles/123"},{"title":"华尔街见闻早餐FM-Radio | 2026年4月10日","uri":"https://wallstreetcn.com/articles/999"}]}}
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
  mkdir -p "$(dirname "$READ_URLS_FILE")"
  touch "$READ_URLS_FILE"
}

filter_unread_items() {
  local items_json="$1"
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
  printf '%s\n' "$items_json" | jq -r '.[].url' | while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if ! grep -Fqx "$url" "$READ_URLS_FILE"; then
      printf '%s\n' "$url" >> "$READ_URLS_FILE"
    fi
  done
}

run_self_test() {
  local wallstreetcn_hot
  local sspai_hot
  local longbridge_hot
  local payload
  local state_file

  state_file="$(mktemp)"
  READ_URLS_FILE="$state_file"

  wallstreetcn_hot="$(self_test_hot_fixture | transform_wallstreetcn_hot)"
  sspai_hot="$(self_test_sspai_fixture | transform_sspai_hot)"
  longbridge_hot="$(self_test_longbridge_fixture | transform_longbridge_hot)"

  [[ "$wallstreetcn_hot" == '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' ]] || exit 1
  [[ "$sspai_hot" == '[{"title":"SSPAI article","url":"https://sspai.com/post/789","summary":"SSPAI summary"}]' ]] || exit 1
  [[ "$longbridge_hot" == '[{"title":"Longbridge event","url":"https://web.lbkrs.com/zh-CN/events/3125600?channel=n3125600","summary":"Longbridge overview"}]' ]] || exit 1

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot")"
  sspai_hot="$(filter_unread_items "$sspai_hot")"
  longbridge_hot="$(filter_unread_items "$longbridge_hot")"
  mark_items_as_read "$wallstreetcn_hot"
  mark_items_as_read "$sspai_hot"
  mark_items_as_read "$longbridge_hot"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot")"
  filter_payload "$payload"

  rm -f "$state_file"
}

main() {
  require_cmd bash
  require_cmd curl
  require_cmd jq

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        SOURCE="${2:-}"
        shift 2
        ;;
      --timeout)
        TIMEOUT="${2:-}"
        shift 2
        ;;
      --state-file)
        READ_URLS_FILE="${2:-}"
        shift 2
        ;;
      --compact)
        COMPACT="1"
        shift
        ;;
      --pretty-print)
        COMPACT="0"
        shift
        ;;
      --self-test)
        SELF_TEST="1"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  ensure_state_file

  local wallstreetcn_hot='[]'
  local sspai_hot='[]'
  local longbridge_hot='[]'
  local payload

  if [[ "$SELF_TEST" == "1" ]]; then
    payload="$(run_self_test)"
    print_json "$payload"
    return
  fi

  case "$SOURCE" in
    all|wallstreetcn-hot)
      wallstreetcn_hot="$(fetch_json "$WALLSTREETCN_HOT_URL" | transform_wallstreetcn_hot)"
      ;;
  esac

  case "$SOURCE" in
    all|sspai-hot)
      sspai_hot="$(fetch_json "$(build_sspai_url)" | transform_sspai_hot)"
      ;;
  esac

  case "$SOURCE" in
    all|longbridge-hot)
      longbridge_hot="$(
        fetch_json_post \
          "https://m.lbkrs.com/api/forward/v1/event/events/feed" \
          "$(build_longbridge_hot_payload)" \
        | transform_longbridge_hot
      )"
      ;;
  esac

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot")"
  sspai_hot="$(filter_unread_items "$sspai_hot")"
  longbridge_hot="$(filter_unread_items "$longbridge_hot")"

  mark_items_as_read "$wallstreetcn_hot"
  mark_items_as_read "$sspai_hot"
  mark_items_as_read "$longbridge_hot"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot")"
  payload="$(filter_payload "$payload")"
  print_json "$payload"
}

main "$@"
