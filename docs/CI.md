# CI

GitHub release builds need one repository secret:

- `NOTERR_SYNC_URL`

Use the deployed Cloudflare Worker URL, for example:

```text
https://noterr-sync.YOUR-SUBDOMAIN.workers.dev
```

The app encrypts notes locally before upload. Cloudflare D1 stores only encrypted payloads, nonces, MACs, revisions, device ids, and timestamps.
