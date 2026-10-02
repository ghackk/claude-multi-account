# Usage history and reporting

The account menu installs a local SQLite history and a background reporter. Node.js 22.13 or newer is required for `node:sqlite`. The account manager still works if reporting cannot start.

Choose **U** in either menu for the hosted dashboard, enable/disable controls, or merging another PC's `usage.db`. Windows uses the hidden **Claude usage history** task, macOS uses the **com.ghackk.multi-claude.usage** LaunchAgent, and Linux uses a marked cron entry. They run every 15 minutes. Launchers and Claude SessionStart/SessionEnd hooks also trigger background sweeps. Disabling reporting persists across menu restarts. `MULTI_CLAUDE_NO_REPORT=1` disables a launcher invocation; the menu's disable control also disables scheduled reporting.

History is retained at `~/claude-usage-history/usage.db`, outside profile directories. Reporter files are installed into `~/claude-accounts/`. The local dashboard binds only to `127.0.0.1:3142`; the shared dashboard is at https://pair.ghackk.com and requires the owner's password.

## What is recorded

- Email, account UUID, profile instance, hashed device fingerprint, hostname, OS, and OS username.
- Reply IDs, session IDs, UTC dates, model names, and input/output/cache-read/cache-write counters. No prompts, responses, or transcript text are uploaded.
- Claude Code's per-profile `stats-cache.json` counters and last-computed date.
- Account-wide usage percentages and reset times, sampled at most every 15 minutes per account. Only unexpired local access tokens are used, only against Anthropic's endpoint. The reporter never refreshes credentials or uploads them to the pairing server.
- Send, receive, backup, and restore events with device lineage. Transfers from older clients without metadata appear only in the old aggregate health statistics.

Each `(email, reply ID)` is counted once, taking the maximum of each token counter across repeated content blocks, resumed transcripts, resets, restores, and PCs. Device totals show the first device that reported a reply; this is an observation, not proof of its execution location. A copied reply can appear in several devices' observed counts while contributing only once to the account's total.

All dashboard date ranges use UTC calendar days, including today. History includes subagent replies. The stats comparison displays each cache snapshot beside the retained account history across devices, so stale caches, resets, copied profiles, and subagents can explain differences. Limits are a separate account-wide signal, not token billing data. A failed limit request keeps the last good sample and visibly marks its status.

## Dashboard and device recognition

The dashboard has separate overview, account, device/person, model, IP-history, and activity views. Search matches emails, person/device names, system users, fingerprints, and observed IP addresses. Device names and person names are edited separately and survive later reports. Names set on a local dashboard are local; names set on the shared dashboard are stored on the server.

The device fingerprint hashes Windows MachineGuid, macOS IOPlatformUUID, or Linux machine-id. The raw identifier is not uploaded. An application uninstall/reinstall normally keeps this identity; OS reinstalls, cloned machines, or the local-ID fallback can change or duplicate it. It is a recognition aid, not authentication.

IP history retains every observed address with first/last-seen times, linked to a device and the emails reported from it. Only the server's connection address, or the address supplied by its trusted local reverse proxy, is recorded. These are report/transfer observations, not verified Claude sign-ins. Historical IPs from before recording started are unavailable. IP history is all-time, independent of the token date filter.

Shared history, names, IPs, and health pages require the administrator's dashboard login. Ordinary reporters can submit usage but cannot read that dashboard. Reports are self-reported data: the current reporting protocol does not authenticate ownership of an email or fingerprint. Do not use these records as security or billing evidence. No dashboard password or session is included in the public package.

## Commands

```sh
node ~/claude-accounts/usage/report.js collect   # local collection only
node ~/claude-accounts/usage/report.js           # collect, sample limits, upload
node ~/claude-accounts/usage/report.js serve     # local dashboard
node ~/claude-accounts/usage/report.js json      # retained history as JSON
node ~/claude-accounts/usage/report.js disable
node ~/claude-accounts/usage/report.js enable
node ~/claude-accounts/usage/report.js merge /path/to/other/usage.db
```

Copy a closed database, or use SQLite's backup command when moving history from a running PC. Do not copy only the main `.db` while a WAL writer is active. The merge reads the source without modifying it and is safe to repeat. It refuses old rows with no device attribution; run collection on the source PC first.

`CLAUDE_USAGE_HOME`, `CLAUDE_USAGE_DIR`, `CLAUDE_USAGE_PORT`, and `MULTI_CLAUDE_REPORT_URL` support isolated testing. Upload URLs must use HTTPS except on loopback. Failed uploads leave replies pending and are retried on the next sweep. `CLAUDE_USAGE_VERBOSE=1` prints operational errors without credential values.

## Verification

Run `npm test`. GitHub Actions runs on Apple Silicon macOS, Intel macOS, Linux, and Windows. Mac tests use a temporary Keychain with synthetic credentials and verify the LaunchAgent runs. The Unix menu tests exercise creation, launch, rename, export/import, default-account metadata, deletion, and fresh installation. Private server tests additionally cover validation, per-device observations, transfer lineage, authentication, CSRF, payload limits, pairing passphrases, credential-free history, and actual client uploads/retries.
