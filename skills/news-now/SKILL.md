---
name: news-now
description: Fetch and normalize Chinese information-flow content from WallstreetCN, SSPAI, and Longbridge. Use when Codex needs WallstreetCN hot articles, SSPAI hot articles, or Longbridge key events, then strip noisy API fields, filter out previously fetched URLs, and return agent-ready JSON with `title`, `url`, and optional `summary`. Trigger on requests such as "获取华尔街见闻热门", "获取少数派热门", "获取 longbridge 关键事件", or "输出精简 news feed JSON".
---

# News Now

## Overview

Fetch WallstreetCN, SSPAI, and Longbridge content feeds, remove already seen articles, and normalize the remaining items into compact JSON for downstream agent use.

Return `title` and `url` for each article item, and include `summary` only when the source provides a usable summary. Drop all other API fields.

## Quick Start

Run the bundled script:

```bash
bash skills/news-now/scripts/fetch_feed.sh
```

By default the script fetches all supported sources and prints compact JSON with three top-level keys:

- `wallstreetcn_hot`
- `sspai_hot`
- `longbridge_hot`

## Supported Sources

Use `--source` to limit the fetch to one source:

- `all`
- `wallstreetcn-hot`
- `sspai-hot`
- `longbridge-hot`

Example:

```bash
bash skills/news-now/scripts/fetch_feed.sh --source sspai-hot
```

Use `--pretty-print` when you want formatted output:

```bash
bash skills/news-now/scripts/fetch_feed.sh --pretty-print
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
- For WallstreetCN hot, drop articles whose title contains `华尔街见闻早餐`.
- For SSPAI hot, drop articles whose title contains `福利派`.
- For Longbridge hot, set `filter.time_end` to the current epoch time in seconds, and `filter.time_start` to `time_end - 86400`.
- For Longbridge hot, build the URL as `https://web.lbkrs.com/zh-CN/events/{id}?channel=n{id}` using `event.id`.
- For SSPAI hot, return the source `summary` field directly as `summary`, or `""` when missing.
- For Longbridge hot, use `event.overview` as `summary`.
- If a source does not provide a summary field, omit `summary` unless that source explicitly requires an empty string.
- Keep URLs absolute.
- Do not add metadata such as author, id, timestamps, tags, counts, or source names unless the user explicitly asks for them.

## Read Tracking

Track previously fetched article URLs in `skills/news-now/data/read_urls.txt` by default.

Apply these rules:

- Create the file automatically if it does not exist.
- Before returning articles, compare each URL against the state file with `grep`.
- Return only URLs that are not already recorded.
- After returning unread articles, append their URLs to the state file.
- Use `--state-file /path/to/file` to override the default state file location when needed.

## Execution Notes

- SSPAI `created_at` must be the current epoch time in seconds. The script computes it at runtime automatically.
- Longbridge payload `time_end` must be the current epoch time in seconds, and `time_start` must be one day earlier. The script computes both at runtime automatically.
- The script depends on `bash`, `curl`, and `jq`.
- If `curl` or `jq` is missing, stop and ask the user to install it before running the script.
- If the network is unavailable, fail clearly instead of returning guessed content.

## Resources

### scripts/

- [`scripts/fetch_feed.sh`](/Users/yangyue/work/my-skills/skills/news-now/scripts/fetch_feed.sh): Fetch and normalize the three feeds with shell tools.

### data/

- [`data/read_urls.txt`](/Users/yangyue/work/my-skills/skills/news-now/data/read_urls.txt): Default state file used to track fetched article URLs.

## Validation

Use the built-in fixture-based self-test when you need to verify parsing logic without network access:

```bash
bash skills/news-now/scripts/fetch_feed.sh --self-test
```
