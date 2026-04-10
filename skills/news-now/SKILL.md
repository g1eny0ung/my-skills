---
name: news-now
description: Fetch and normalize Chinese information-flow content from WallstreetCN and SSPAI. Use when Codex needs WallstreetCN hot articles or SSPAI hot articles, then strip noisy API fields, filter out previously fetched URLs, and return agent-ready JSON with `title`, `url`, and optional `description`. Trigger on requests such as "获取华尔街见闻热门", "获取少数派热门", "整理资讯列表", "过滤已读文章", or "输出精简 news feed JSON".
---

# News Now

## Overview

Fetch WallstreetCN and SSPAI content feeds, remove already seen articles, and normalize the remaining items into compact JSON for downstream agent use.

Return `title` and `url` for each article item, and include `description` only when the source provides a usable summary. Drop all other API fields.

## Quick Start

Run the bundled script:

```bash
bash skills/news-now/scripts/fetch_feed.sh
```

By default the script fetches all supported sources and prints a JSON object with two top-level keys:

- `wallstreetcn_hot`
- `sspai_hot`

## Supported Sources

Use `--source` to limit the fetch to one source:

- `all`
- `wallstreetcn-hot`
- `sspai-hot`

Example:

```bash
bash skills/news-now/scripts/fetch_feed.sh --source sspai-hot
```

## Output Rules

Return items in this shape:

```json
{
  "title": "Article title",
  "url": "https://..."
}
```

or, when a summary exists:

```json
{
  "title": "Article title",
  "url": "https://...",
  "description": "Short summary"
}
```

Apply these source-specific rules:

- For WallstreetCN hot, read from `data.day_items`.
- For SSPAI hot, read from `data`.
- If a source does not provide a summary field, omit `description` instead of inventing content.
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
