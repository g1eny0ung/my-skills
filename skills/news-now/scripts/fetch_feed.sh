#!/usr/bin/env bash

set -euo pipefail

SOURCE="all"
TIMEOUT="15"
COMPACT="1"
OUTPUT_FORMAT="json"
LONGBRIDGE_SCORE_MIN="6"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/data"
READ_URLS_FILE="$STATE_DIR/read_urls.txt"

# Source shared library
source "$SCRIPT_DIR/fetch_feed_common.sh"

WALLSTREETCN_HOT_URL="https://api-one-wscn.awtmt.com/apiv1/content/articles/hot?period=all"
SSPAI_HOT_URL="https://sspai.com/api/v1/article/hot/page/get"

usage() {
  cat <<'EOF'
Usage: fetch_feed.sh [--source all|wallstreetcn-hot|sspai-hot|longbridge-hot] [--timeout seconds] [--state-file path] [--pretty-print] [--txt] [--longbridge-score-min number]
EOF
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

build_sspai_url() {
  local created_at
  created_at="$(date +%s)"
  printf '%s?offset=0&limit=10&created_at=%s\n' "$SSPAI_HOT_URL" "$created_at"
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

  ensure_state_file "$READ_URLS_FILE"

  local wallstreetcn_hot='[]'
  local sspai_hot='[]'
  local longbridge_hot='[]'
  local payload

  case "$SOURCE" in
    all|wallstreetcn-hot)
      wallstreetcn_hot="$(fetch_json "$WALLSTREETCN_HOT_URL" | transform_wallstreetcn_hot)"
      wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot" "$READ_URLS_FILE")"
      mark_items_as_read "$wallstreetcn_hot" "$READ_URLS_FILE"
      ;;
  esac

  case "$SOURCE" in
    all|sspai-hot)
      sspai_hot="$(fetch_json "$(build_sspai_url)" | transform_sspai_hot)"
      sspai_hot="$(filter_unread_items "$sspai_hot" "$READ_URLS_FILE")"
      mark_items_as_read "$sspai_hot" "$READ_URLS_FILE"
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
      longbridge_hot="$(filter_unread_items "$longbridge_hot" "$READ_URLS_FILE")"
      mark_items_as_read "$longbridge_hot" "$READ_URLS_FILE"
      ;;
  esac

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot" "$longbridge_hot")"
  payload="$(filter_payload "$payload" "$SOURCE")"
  print_output "$payload" "$OUTPUT_FORMAT" "$COMPACT"
}

main "$@"
