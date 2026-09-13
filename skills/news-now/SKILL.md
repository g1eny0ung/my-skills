---
name: news-now
description: Fetch and normalize information-flow content from WallstreetCN, SSPAI, Longbridge, V2EX, and Hacker News. Use when the user wants WallstreetCN hot articles, SSPAI hot articles, Longbridge key events, V2EX latest shares, or Hacker News front page stories, then strip noisy API fields, filter out previously fetched URLs, and return agent-ready JSON with `title`, `url`, and optional `summary`. Trigger on requests such as "获取华尔街见闻热门", "获取少数派热门", "获取 longbridge 关键事件", "获取 V2EX 最新分享", "获取 Hacker News 热帖", or "输出精简 news feed JSON".
---

# News Now

## Overview

Fetch WallstreetCN, SSPAI, Longbridge, V2EX, and Hacker News content feeds, remove already seen articles, and normalize the remaining items into compact JSON for downstream agent use.

Return `title` and `url` for each article item, and include `summary` only when the source provides a usable summary. Drop all other API fields.

## Quick Start

Run the bundled script:

```bash
bash scripts/fetch_feed.sh
```

By default the script fetches all supported sources and prints compact JSON with three top-level keys:

- `wallstreetcn_hot`
- `sspai_hot`
- `longbridge_hot`
- `v2ex_hot`
- `hackernews_hot`

## Supported Sources

Use `--source` to limit the fetch to one source:

- `all`
- `wallstreetcn-hot`
- `sspai-hot`
- `longbridge-hot`
- `v2ex-hot`
- `hackernews-hot`

Example:

```bash
bash scripts/fetch_feed.sh --source sspai-hot
```

Use `--pretty-print` when you want formatted output:

```bash
bash scripts/fetch_feed.sh --pretty-print
```

Use `--txt` when you want plain-text output:

```bash
bash scripts/fetch_feed.sh --txt
```

Use `--longbridge-score-min` to specify a custom minimum score for Longbridge hot events (must be a number ≤ 10; defaults to 6):

```bash
bash scripts/fetch_feed.sh --source longbridge-hot --longbridge-score-min 5
```

## Output Rules

Return items in this shape:

```json
{
  "title": "Article title",
  "url": "https://..."
}
```

or, for sources with summaries:

```json
{
  "title": "Article title",
  "url": "https://...",
  "summary": "Short summary"
}
```

```json
{
  "title": "Event title",
  "url": "https://...",
  "summary": "Overview text"
}
```

Apply these source-specific rules:

- For WallstreetCN hot, read from `data.day_items`.
- For SSPAI hot, read from `data`.
- For Longbridge hot, POST to `https://m.lbkrs.com/api/forward/v1/event/events/feed` and read from `data.events`.
- For V2EX hot, GET `https://www.v2ex.com/feed/{node}.json` for each node in `create`, `ideas`, `programmer`, `share`, read each response's `items`, merge them, dedupe by `url`, sort by `date_modified` (falling back to `date_published`) descending, and keep at most 30 items.
- For Hacker News hot, GET `https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30` and read from `hits`.
- For WallstreetCN hot, drop articles whose title contains `华尔街见闻早餐`.
- For SSPAI hot, drop articles whose title contains `福利派`.
- For Longbridge hot, set `filter.time_end` to the current epoch time in seconds, and `filter.time_start` to `time_end - 86400`.
- For Longbridge hot, set `filter.score_max` to 10 and `filter.score_min` to a user-specified value (defaults to 6).
- For Longbridge hot, build the URL as `https://web.lbkrs.com/zh-CN/events/{id}?channel=n{id}` using `event.id`.
- For SSPAI hot, return the source `summary` field directly as `summary`, or `""` when missing.
- For Longbridge hot, use `event.overview` as `summary`.
- For V2EX hot and Hacker News hot, do not output `summary`.
- For Hacker News hot, use `hit.url` as the item URL; when `hit.url` is null, fall back to `https://news.ycombinator.com/item?id={objectID}`.
- If a source does not provide a summary field, omit `summary` unless that source explicitly requires an empty string.
- Keep URLs absolute.
- Do not add metadata such as author, id, timestamps, tags, counts, or source names unless the user explicitly asks for them.

## Read Tracking

Track previously fetched article URLs in `data/read_urls.txt` under this skill's directory by default.

Apply these rules:

- Create the file automatically if it does not exist.
- Before returning articles, compare each URL against the state file with `grep`.
- Return only URLs that are not already recorded.
- After returning unread articles, append their URLs to the state file.
- Use `--state-file /path/to/file` to override the default state file location when needed.

## Execution Notes

- SSPAI `created_at` must be the current epoch time in seconds. The script computes it at runtime automatically.
- Longbridge payload `time_end` must be the current epoch time in seconds, and `time_start` must be one day earlier. The script computes both at runtime automatically.
- For Longbridge hot events, you can specify a custom `score_min` value (defaults to 6) using `--longbridge-score-min`. The value must be a valid number ≤ 10.
- The script depends on `bash`, `curl`, and `jq`.
- If `curl` or `jq` is missing, stop and ask the user to install it before running the script.
- If the network is unavailable, fail clearly instead of returning guessed content.
- V2EX and Hacker News endpoints may be unreachable on restricted networks (for example, mainland China without a proxy); if their fetch fails, report the failure for that source instead of guessing.

## Resources

### scripts/

- [`scripts/fetch_feed.sh`](scripts/fetch_feed.sh): Fetch and normalize the three feeds with shell tools.
- [`scripts/fetch_feed_test.sh`](scripts/fetch_feed_test.sh): Dedicated test script containing all fixture-based tests for the feed parsing logic.

### data/

- [`data/`](data/): Contains the runtime state file `read_urls.txt` used to track fetched article URLs. The file is created automatically on first run and is not tracked in git.

## Validation

Use the dedicated test script when you need to verify parsing logic without network access:

```bash
bash scripts/fetch_feed_test.sh
```

The script prints only the test result summary (`OK: <n> assertions passed.`).
