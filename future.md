# Claude Account Pairing System

## Context
The existing Export/Import via clipboard token works but requires copy-pasting ~8.5K characters. The user wants a short pairing code system (like TV app pairing) where Laptop A gets a code like `A7X-K9M4PX` and Laptop B just enters it — with encryption, auto-expiry, and one-time use. Server hosted at `pair.ghackk.com` on user's Ubuntu VPS.

**Distribution model:** Two repos — private has everything, public has only the account manager. Pairing logic is fetched on-demand from server (never in public repo), runs in memory, deleted after use, obfuscated in transit.

## Architecture

### Folder Structure (Private Repo)
```
claude-multi-account-private/
├── public/                        ← synced to public repo
│   ├── claude-menu.ps1            ← P/R menu entries fetch from server
│   ├── claude-menu.bat
│   ├── unix/
│   │   ├── claude-menu.sh
│   │   └── install.sh
│   ├── README.md
│   └── .gitignore
├── server/                        ← PRIVATE: pairing server
│   ├── server.js                  ← Node.js API + serves client scripts
│   ├── package.json
│   └── client-scripts/            ← pairing logic served on-demand
│       ├── pair-export.ps1
│       ├── pair-import.ps1
│       ├── pair-export.sh
│       └── pair-import.sh
├── deploy/                        ← PRIVATE: server deployment
│   ├── claude-pair.service
│   └── pair.ghackk.com.nginx
├── sync-public.sh                 ← copies public/ → public repo + pushes
└── future.md
```

### Two Git Repos
| Repo | Visibility | Contains |
|------|-----------|----------|
| `ghackk/claude-multi-account` | Public | `public/` folder contents only |
| `ghackk/claude-multi-account-private` | Private | Everything — server, client scripts, deploy |

## Security Model

### Pairing Code
- **Format:** `{3-char route}-{6-char passphrase}` (e.g., `A7X-K9M4PX`)
- Route = server lookup key (server-side generated)
- Passphrase = AES decryption key (client-side generated, **never sent to server**)
- Server stores only opaque ciphertext it cannot decrypt
- Both endpoints use POST → codes never in URLs/logs
- One-time use + auto-expiry (default 10 min)
- Alphabet: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0/O/1/I/L)

### Code Protection (5 layers)
1. **Not in repo** — pairing code never published, can't be forked
2. **Obfuscated in transit** — server sends encoded/compressed, not plain text
3. **Deleted after use** — runs in memory, not saved to disk
4. **Useless without server** — pairing functions call pair.ghackk.com, dead without it
5. **Server-controlled** — you can change served code anytime, moving target

### Encryption
- **Algorithm:** AES-256-CBC
- **Key derivation:** PBKDF2-HMAC-SHA256, 100K iterations, salt = `"claude-pair-v1"`
- **Key material:** 48 bytes (32 key + 16 IV)
- PowerShell: `Rfc2898DeriveBytes` → `GetBytes(32)` + `GetBytes(16)`
- Bash: `openssl kdf` (3.0+) or `python3 hashlib.pbkdf2_hmac` fallback

## Implementation

### Phase 1: Private repo setup
- Create `ghackk/claude-multi-account-private` on GitHub
- Set up folder structure
- Move existing code into `public/` subfolder

### Phase 2: Server (`server/server.js`)
- Node.js, zero deps (stdlib `http` + `crypto` + `fs`)
- In-memory `Map` with TTL cleanup every 30s
- **API endpoints:**
  - `POST /api/store` → `{ ciphertext }` → `{ route, expires_in }`
  - `POST /api/fetch` → `{ route }` → `{ ciphertext }`, deletes entry
  - `GET /api/health` → `{ status, active, uptime }`
  - `GET /client/pair-export.ps1` → serves obfuscated PS pairing export script
  - `GET /client/pair-import.ps1` → serves obfuscated PS pairing import script
  - `GET /client/pair-export.sh` → serves obfuscated Bash pairing export script
  - `GET /client/pair-import.sh` → serves obfuscated Bash pairing import script
- **Limits:** 16KB payload, 100 entries, 10 req/min/IP
- **Obfuscation:** reads `client-scripts/*.ps1|sh`, Base64 encodes + reverses + wraps, serves as text
- Listens `127.0.0.1:3141`

### Phase 3: Deploy configs (`deploy/`)
- `claude-pair.service` — systemd unit for Node.js server
- `pair.ghackk.com.nginx` — reverse proxy `:3141`, TLS via certbot, `client_max_body_size 16k`

### Phase 4: PowerShell client changes (`public/claude-menu.ps1`)
1. **Refactor** — Extract `Build-ExportToken($name)` and `Apply-ImportToken($token)` helpers
2. **Rewrite** `Export-Profile`/`Import-Profile` to call helpers (no behavior change)
3. **Add menu entries P and R** that:
   - Fetch obfuscated script from `https://pair.ghackk.com/client/pair-{action}.ps1`
   - Decode in memory
   - Execute via `Invoke-Expression`
   - Script uses `Build-ExportToken`/`Apply-ImportToken` helpers already in scope
4. Add `$PAIR_SERVER = "https://pair.ghackk.com"` constant

### Phase 5: Bash client changes (`public/unix/claude-menu.sh`)
- Same refactor: `build_export_token`/`apply_import_token` helpers
- Menu entries P/R fetch from server via `curl`, decode, `eval`
- Pairing scripts use `openssl` for AES + `curl` for HTTP

### Phase 6: Sync script (`sync-public.sh`)
```bash
#!/bin/bash
cp -r public/* ../claude-multi-account/
cd ../claude-multi-account
git add -A && git commit -m "Sync update" && git push
```

## Client Script Flow (how P/R work)

```
User picks "P" (Pair Export) in menu
    ↓
claude-menu.ps1:
    $raw = Invoke-RestMethod "https://pair.ghackk.com/client/pair-export.ps1"
    $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw.Reverse()))
    Invoke-Expression $decoded
    ↓
pair-export.ps1 (in memory, never on disk):
    - account selection (uses Show-Accounts already loaded)
    - Build-ExportToken (helper already in scope)
    - generate 6-char passphrase
    - PBKDF2 → AES encrypt
    - POST ciphertext to /api/store
    - display pairing code: A7X-K9M4PX
    ↓
Script gone from memory. Nothing on disk.
```

## Files to Create/Modify

| File | Location | Action |
|------|----------|--------|
| `server/server.js` | Private repo | Create — Node.js server + script serving |
| `server/package.json` | Private repo | Create — metadata |
| `server/client-scripts/pair-export.ps1` | Private repo | Create — PS pairing export logic |
| `server/client-scripts/pair-import.ps1` | Private repo | Create — PS pairing import logic |
| `server/client-scripts/pair-export.sh` | Private repo | Create — Bash pairing export logic |
| `server/client-scripts/pair-import.sh` | Private repo | Create — Bash pairing import logic |
| `deploy/claude-pair.service` | Private repo | Create — systemd unit |
| `deploy/pair.ghackk.com.nginx` | Private repo | Create — nginx config |
| `sync-public.sh` | Private repo | Create — sync to public repo |
| `public/claude-menu.ps1` | Both repos | Modify — refactor helpers + add P/R menu |
| `public/unix/claude-menu.sh` | Both repos | Modify — same |

## Cross-platform Compatibility
- PS exports `CLAUDE_TOKEN_GZ:` format, Bash exports `CLAUDE_TOKEN:` format
- Both import functions handle both formats
- PBKDF2 params identical → PS pair code works on Bash and vice versa

## Verification
1. `curl https://pair.ghackk.com/api/health` → `{"status":"ok"}`
2. `curl https://pair.ghackk.com/client/pair-export.ps1` → obfuscated blob (not readable)
3. PS: Pair-Export → Pair-Import on another machine → profile logged in
4. Bash: Same test
5. Cross-platform: PS → Bash and vice versa
6. Expiry: wait >10 min → code returns 404
7. One-time: use code twice → second returns 404
8. Existing E/I still work unchanged

## Deployment Steps (VPS)
1. DNS: A record `pair.ghackk.com` → VPS IP
2. SSH to VPS: `mkdir -p /opt/claude-pair`
3. Copy `server/` contents to `/opt/claude-pair/`
4. Copy `deploy/claude-pair.service` to `/etc/systemd/system/`
5. `systemctl daemon-reload && systemctl enable --now claude-pair`
6. Copy `deploy/pair.ghackk.com.nginx` to `/etc/nginx/sites-available/`
7. `ln -s /etc/nginx/sites-available/pair.ghackk.com /etc/nginx/sites-enabled/`
8. `certbot --nginx -d pair.ghackk.com`
9. `nginx -t && systemctl reload nginx`
10. Test health endpoint
