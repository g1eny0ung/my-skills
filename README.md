# my-skills

Personal skill repository.

## Installation

```sh
npx skills add g1eny0ung/my-skills
# Or install a single skill
npx skills add g1eny0ung/my-skills --skill news-now
```

## Skills

- `news-now`

  Fetch WallstreetCN, SSPAI, and Longbridge hot articles, filter out URLs that have already been seen, and return compact JSON for agent use.

## Notes

- Skills live under `skills/`.
- Usage details belong in each skill's `SKILL.md`.
- `news-now`
  - `news-now` depends on `bash`, `curl`, and `jq`.
  - `news-now` tracks fetched URLs in `skills/news-now/data/read_urls.txt` by default.

## Statements

### About news-now skill

- Please do not query frequently to avoid putting pressure on data source servers
- This skill is for personal learning purposes only, please do not abuse it
