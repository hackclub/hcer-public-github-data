# HCer Public Github Data

Scripts and tooling to gather public GitHub data to calculate stats like whether Hack Clubbers code more during events like High Seas / Arcade than before.

## Tools

### Proxy

Make requests to `/gh/` to proxy requests to the GitHub API. You must pass `X-Proxy-API-Key` as an HTTP header with the value `proxy-api-key` (found in Rails credentials).

Example paths:

- `/gh/users/octocat`
- `/gh/search/repositories?q=rails+in:name,description,readme`
- `/gh/graphql`
