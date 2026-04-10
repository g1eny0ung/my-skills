#!/usr/bin/env bash

set -euo pipefail

SOURCE="all"
TIMEOUT="15"
COMPACT="0"
SELF_TEST="0"
USER_AGENT="Mozilla/5.0 (compatible; news-now/1.0)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/data"
READ_URLS_FILE="$STATE_DIR/read_urls.txt"

WALLSTREETCN_HOT_URL="https://api-one-wscn.awtmt.com/apiv1/content/articles/hot?period=all"
SSPAI_HOT_URL="https://sspai.com/api/v1/article/hot/page/get"

usage() {
  cat <<'EOF'
Usage: fetch_feed.sh [--source all|wallstreetcn-hot|sspai-hot] [--timeout seconds] [--state-file path] [--compact] [--self-test]
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

transform_wallstreetcn_hot() {
  jq -c '
    [
      .data.day_items[]?
      | select(.title and .uri)
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
      | (
        {
          title: .title,
          url: ("https://sspai.com/post/" + (.id | tostring))
        }
        + if (.summary // "") != "" then { description: .summary } else {} end
      )
    ]
  '
}

build_sspai_url() {
  local created_at
  created_at="$(date +%s)"
  printf '%s?offset=0&limit=10&created_at=%s\n' "$SSPAI_HOT_URL" "$created_at"
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

  jq -n \
    --argjson wallstreetcn_hot "$wallstreetcn_hot" \
    --argjson sspai_hot "$sspai_hot" \
    '
      {
        wallstreetcn_hot: $wallstreetcn_hot,
        sspai_hot: $sspai_hot
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
    *)
      echo "Unsupported source: $SOURCE" >&2
      exit 1
      ;;
  esac
}

self_test_hot_fixture() {
  cat <<'EOF'
{"data":{"day_items":[{"title":"Hot article","uri":"https://wallstreetcn.com/articles/123"}]}}
EOF
}

self_test_sspai_fixture() {
  cat <<'EOF'
{"data":[{"id":789,"title":"SSPAI article","summary":"SSPAI summary"}]}
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
  local payload
  local state_file

  state_file="$(mktemp)"
  READ_URLS_FILE="$state_file"

  wallstreetcn_hot="$(self_test_hot_fixture | transform_wallstreetcn_hot)"
  sspai_hot="$(self_test_sspai_fixture | transform_sspai_hot)"

  [[ "$wallstreetcn_hot" == '[{"title":"Hot article","url":"https://wallstreetcn.com/articles/123"}]' ]] || exit 1
  [[ "$sspai_hot" == '[{"title":"SSPAI article","url":"https://sspai.com/post/789","description":"SSPAI summary"}]' ]] || exit 1

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot")"
  sspai_hot="$(filter_unread_items "$sspai_hot")"
  mark_items_as_read "$wallstreetcn_hot"
  mark_items_as_read "$sspai_hot"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot")"
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

  wallstreetcn_hot="$(filter_unread_items "$wallstreetcn_hot")"
  sspai_hot="$(filter_unread_items "$sspai_hot")"

  mark_items_as_read "$wallstreetcn_hot"
  mark_items_as_read "$sspai_hot"

  payload="$(build_payload "$wallstreetcn_hot" "$sspai_hot")"
  payload="$(filter_payload "$payload")"
  print_json "$payload"
}

main "$@"
