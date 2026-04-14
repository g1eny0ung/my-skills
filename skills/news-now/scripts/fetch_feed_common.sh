#!/usr/bin/env bash

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
