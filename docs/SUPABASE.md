# Supabase and Codex

Noterr currently syncs through Cloudflare Worker + D1, not Supabase.

If the old hosted Supabase project is paused, current Noterr builds should keep
working because they use:

- `NOTERR_SYNC_URL`
- `cloudflare/noterr-sync-worker.js`
- Cloudflare D1 table schema in `cloudflare/schema.sql`

## Self-hosted Supabase

Your self-hosted Supabase Studio/API at `supabase.skillsgeek.com` can be useful
for future projects, but Noterr does not need to migrate there right now.

To let Codex work with that self-hosted database in the future, use one of these
approaches:

1. Direct Postgres MCP/connector using a read-only or development database user.
2. A small self-hosted MCP bridge that connects to your Supabase Postgres.
3. Supabase hosted remote MCP only for hosted Supabase projects.

Do not commit database passwords, service-role keys, or personal access tokens
to this repo.

## Hosted Supabase MCP

For hosted Supabase projects, Supabase documents the remote MCP endpoint:

```text
https://mcp.supabase.com/mcp
```

Use project scoping and read-only mode for safety when possible:

```text
https://mcp.supabase.com/mcp?project_ref=YOUR_PROJECT_REF&read_only=true
```

Self-hosted Supabase usually needs a direct Postgres connection or a custom MCP
bridge instead of the hosted Supabase MCP endpoint.
