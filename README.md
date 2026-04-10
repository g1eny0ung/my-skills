# my-skills

Personal skill repository.

## Skills

- `news-now`
  Fetch WallstreetCN hot articles and SSPAI hot articles, filter out URLs that have already been seen, and return compact JSON for agent use.

## Notes

- Skills live under `skills/`.
- Usage details belong in each skill's `SKILL.md`.
- `news-now` depends on `bash`, `curl`, and `jq`.
- `news-now` tracks fetched URLs in `skills/news-now/data/read_urls.txt` by default.
