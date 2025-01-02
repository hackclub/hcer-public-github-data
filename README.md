# GitHub Data Scraper

This tool scrapes public GitHub repositories and commits for specified users and their organizations, storing the data in PostgreSQL.

## Setup

1. Install dependencies:
```bash
bun install
```

2. Set up your environment variables in `.env`:
- `DATABASE_URL`: Your PostgreSQL connection URL
- `GITHUB_TOKEN`: Your GitHub personal access token

3. Initialize the database:
```bash
bunx prisma db push
psql -d your_database_name -f prisma/migrations/create_commits_by_user_view.sql
```

## Usage

Run the scraper with one or more GitHub usernames:
```bash
bun run index.ts username1 username2 username3
```

## Database Schema

The data is stored in three main tables:
- `Organization`: Stores organization data
- `Repository`: Stores repository data
- `Commit`: Stores commit data

All data is stored as raw JSON to maintain flexibility for future transformations.

A view `CommitsByUser` is provided for easy querying of commits by user:
```sql
SELECT * FROM "CommitsByUser" WHERE "authorName" = 'username';
```

## Rate Limiting

The tool automatically handles GitHub API rate limits by pausing when necessary.
