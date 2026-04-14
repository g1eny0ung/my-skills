#!/usr/bin/env bash

set -euo pipefail

SOURCE="all"
TIMEOUT="15"
COMPACT="1"
LONGBRIDGE_SCORE_MIN="6"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/data"
READ_URLS_FILE="$STATE_DIR/read_urls.txt"

WALLSTREETCN_HOT_URL="https://api-one-wscn.awtmt.com/apiv1/content/articles/hot?period=all"
SSPAI_HOT_URL="https://sspai.com/api/v1/article/hot/page/get"

usage() {
  cat <<'EOF'
Usage: fetch_feed.sh [--source all|wallstreetcn-hot|sspai-hot|longbridge-hot] [--timeout seconds] [--state-file path] [--pretty-print] [--longbridge-score-min number]
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

build_sspai_url() {
  local created_at
  created_at="$(date +%s)"
  printf '%s?offset=0&limit=10&created_at=%s\n' "$SSPAI_HOT_URL" "$created_at"
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
      --longbridge-score-min)
        LONGBRIDGE_SCORE_MIN="${2:-}"
        shift 2
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

  # Validate longbridge score min
  if ! [[ "$LONGBRIDGE_SCORE_MIN" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid --longbridge-score-min value: must be a number" >&2
    usage >&2
    exit 1
  fi
  if [[ $(jq -n "$LONGBRIDGE_SCORE_MIN > 10") == "true" ]]; then
    echo "Invalid --longbridge-score-min value: must not exceed 10" >&2
    usage >&2
    exit 1
  fi

  ensure_state_file

  local wallstreetcn_hot='[]'
  local sspai_hot='[]'
  local longbridge_hot='[]'
  local payload

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
          "$(build_longbridge_hot_payload "$LONGBRIDGE_SCORE_MIN")" \
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
