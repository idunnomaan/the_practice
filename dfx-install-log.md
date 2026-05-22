# DFX Install Log — Onchain Inc.

**Date started:** 2026-05-10
**Operator:** Abdul
**Partner AI:** Owen
**Studio Stage:** 2 — Infra (see `PROJECT_CONTEXT.md` for the full Studio Stage model)
**Task:** Install ICP toolchain on Windows development machine

> **Scope of this log:** the dev environment build. For the mission, product, and current state of Onchain Inc., read `PROJECT_CONTEXT.md`. For account identifiers, see `identities.md`. This log focuses on commands, decisions, and outcomes of the setup itself.

---

## Decisions made

| Decision | Choice | Rationale |
|---|---|---|
| Linux platform | WSL2 (not WSL1) | Real Linux kernel, DFX-compatible filesystem behavior |
| Distro | Ubuntu 24.04 LTS (via `Ubuntu` default) | Only Ubuntu option in MS Store catalog on this machine; 24.04 is current LTS standard, fully supported by DFX |
| DFX install method | dfxvm (DFX Version Manager) | Official, supports clean version switching, recommended by DFINITY |

---

## Step log

### Step 1 — Diagnose initial state
- Ran `wsl --status` → no output (ambiguous)
- Ran `wsl --version` → printed wsl.exe usage/help text
- **Diagnosis:** wsl.exe stub present, WSL platform not installed. Clean-slate state.

### Step 2 — Install WSL2 + Ubuntu
- First attempt: `wsl --install -d Ubuntu-22.04` → "Invalid distribution name"
- Diagnostic: `wsl --list --online` → only generic `Ubuntu` available (no versioned variants in the catalog on this machine)
- Final command: `wsl --install -d Ubuntu` (PowerShell admin) → installs Ubuntu 24.04 LTS
- Expected: enables WSL platform, VM platform, WSL2 kernel, downloads Ubuntu
- Status: IN PROGRESS

### Step 3 — Create Linux user
- No reboot was required (modern WSL handled platform install + distro install + launch in one go)
- Linux username: `onchain_dev`
- Linux hostname (auto-set): `AbdulBasith`
- Password: set (recorded locally by Abdul, not in this log)
- Opted in to Canonical platform metrics: Y
- Status: COMPLETE

### Step 4 — Update Ubuntu packages
- `cd ~` to land in Linux home (was in /mnt/c/WINDOWS/system32 due to inheriting PowerShell's CWD)
- `sudo apt update` then `sudo apt upgrade -y`
- Benign warning observed: `ldconfig: /usr/lib/wsl/lib/libcuda.so.1 is not a symbolic link` (known harmless WSL/CUDA mount quirk)
- Status: COMPLETE

### Step 5 — Install DFX via dfxvm
- Command: `sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"`
- dfxvm installed to `/home/onchain_dev/.local/share/dfx/`
- dfx 0.32.0 downloaded from `github.com/dfinity/sdk/releases/download/0.32.0/dfx-x86_64-unknown-linux-gnu.tar.gz`
- SHA256 verified: `04229af24ebb7e30bf3a2dba5d69240849338da148f6bf1d56c8a48daaa2dbe3`
- PATH updated via `.profile` and `.bashrc`
- Status: COMPLETE

### Step 6 — Verify DFX
- `source ~/.bashrc` then `dfx --version` → `dfx 0.32.0`
- Status: COMPLETE (binary executes; full toolchain end-to-end verification pending — see Step 7)

### Step 7 — End-to-end verification (FAILED, but in a useful way)
- Ran: `dfx new hello_test --type motoko --no-frontend && cd hello_test && dfx start --background && dfx deploy`
- **Result 1 — DEPRECATION DISCOVERED:** Every dfx command now prints `WARNING: dfx is deprecated, use icp-cli https://cli.internetcomputer.org`
- **Result 2 — PocketIC errors:** `dfx start` failed with three `Failed to initialize PocketIC: HTTP status client error (400 Bad Request)` errors at different ports
- Diagnosis: Likely related — DFINITY's dev attention has moved to icp-cli and dfx 0.32.0's bundled PocketIC may have an API mismatch

### MAJOR ARCHITECTURAL FINDING
DFINITY has officially deprecated dfx in favor of `icp-cli`. Confirmed via:
- Search results showing icp-cli is the modern replacement
- Official install docs at github.com/dfinity/icp-cli
- Forum activity confirming active migration in early 2026

**icp-cli stack:**
- `icp-cli` — core CLI (npm: `@icp-sdk/icp-cli`)
- `ic-wasm` — WebAssembly optimizer (npm: `@icp-sdk/ic-wasm`)
- `ic-mops` — Motoko package manager (npm: `ic-mops`)

**Key changes from dfx:**
- YAML config (was JSON)
- Per-project local networks (was global shared)
- Different command structure (`icp identity default` vs `dfx identity use`)
- **Windows: requires Docker Desktop for local networks**

### Step 8 — Pivot decision: Option A (icp-cli)
- Decision: install icp-cli stack, leave dfx in place (coexists fine, no need to uninstall)
- Status: COMPLETE

### Step 9 — Install icp-cli toolchain in WSL
- System libs verified present: libdbus-1-3, libssl3 (auto-mapped to libssl3t64 on Ubuntu 24.04), ca-certificates
- nvm installed (v0.40.1), Node.js v24.15.0 LTS, npm v11.12.1
- npm globals installed: `@icp-sdk/icp-cli` (v0.2.6), `@icp-sdk/ic-wasm` (v0.9.10), `ic-mops` (CLI v2.13.2 / API v1.3)
- Note: 423 npm packages, several deprecation warnings about `@dfinity/*` JS packages migrating to `@icp-sdk/core/*` — transitive deps, not blocking
- Status: COMPLETE

### Step 10 — Install Docker Desktop on Windows
- Required for icp-cli's per-project local networks
- AMD64 installer (confirmed via `$env:PROCESSOR_ARCHITECTURE`)
- Downloaded from docker.com/products/docker-desktop/
- License: free for our scale (under 250 employees and under $10M revenue)
- Docker account created, signed into desktop app
- WSL2 integration verified from inside Ubuntu:
  - `docker --version` → `Docker version 29.4.2, build 055a478`
  - `docker run hello-world` → image pulled, container ran, "Hello from Docker!" printed
- Status: COMPLETE

### Step 11 — End-to-end verification
- Workspace location: `~/onchain/sandbox/` in Linux home (Linux-native FS for build performance, separate from real client work)
- `icp new hello_icp` → scaffolded with sub-template `hello-world`, backend `motoko`, frontend `react`, network `Default` (not dockerized)
  - Generated 38 files: `backend/` (Motoko canister with mops + Candid), `frontend/app/` (React + Vite + TypeScript), `icp.yaml` project root config
  - Template ships with `CLAUDE.md` + `AGENTS.md` AI-assistant context files out of the box
- `icp network start -d` → local replica started on port 8000 (native binary, no Docker needed for default network on Linux/WSL)
- `icp deploy` → both canisters built, created, installed, synced
  - Backend canister ID: `t63gs-up777-77776-aaaba-cai`
  - Frontend canister ID: `tz2ag-zx777-77776-aaabq-cai`
  - Backend Candid UI: http://tqzl2-p7777-77776-aaaaa-cai.localhost:8000/?id=t63gs-up777-77776-aaaba-cai
  - Frontend app: http://frontend.local.localhost:8000/
- Status: COMPLETE — full toolchain verified end-to-end on icp-cli

### Step 12 — Workspace structure + IDE
- Workspace skeleton in Linux home: `~/onchain/{clients,internal,sandbox}/`
  - `clients/` — per-client repos
  - `internal/` — Onchain Inc tools, products, experiments
  - `sandbox/` — throwaway test projects (currently contains `hello_icp` from Step 11)
- VS Code on Windows updated 1.88.0 → 1.119.0 (May 5 2026, "user setup" installer)
- WSL extension (Microsoft, official) installed
- Motoko language extension (DFINITY Foundation, v0.23.0) installed
- VS Code launched into WSL via `code ~/onchain` from Ubuntu terminal
  - Status indicator confirms `WSL: Ubuntu` connection
  - Integrated terminal lands in Linux at `~/onchain` by default
- Status: COMPLETE

### Step 13 — GitHub account + git/SSH setup
- GitHub username: `idunnomaan` (personal account)
- 2FA: enabled
- Email privacy: enabled (noreply email substitute used for commits)
- Onchain Inc. GitHub Organization: deferred — to be created when first client engagement begins
- SSH key: ed25519, generated in WSL Ubuntu at `~/.ssh/id_ed25519`
  - Passphrase-protected (added retroactively via `ssh-keygen -p -f`)
  - Key fingerprint: `SHA256:SvwGh7tI3UAklg5RCD7SPRKbFZPzP7hBbwdgbZKqKU4`
  - Comment label: `idunnomaan-onchain-dev`
  - Public key uploaded to GitHub Settings → SSH keys with title "WSL Ubuntu — Onchain Dev (AbdulBasith)"
- Git global config:
  - `user.name`: "Abdul Basith"
  - `user.email`: noreply (see Identities table)
  - `init.defaultBranch`: `main`
  - `pull.rebase`: `false` (default merge strategy)
- Connection verified: `ssh -T git@github.com` → "Hi idunnomaan! You've successfully authenticated"
- GitHub host fingerprint verified out-of-band against docs.github.com published value before TOFU acceptance
- Status: COMPLETE
- ROTATION NOTE (2026-05-10): SSH passphrase rotated after initial passphrase was inadvertently exposed in chat transcript. New passphrase stored only in password manager (see Step 14).

### Step 14 — Password manager setup (PENDING)
- Required: secure home for SSH passphrase, Linux user password, GitHub credentials, future API keys, future client secrets
- Candidates: Bitwarden (free, open source) or 1Password ($3/mo, polished UX)
- Once chosen: install desktop app + browser extension + mobile app, migrate existing credentials in
- Add written master-password recovery sheet stored offline (physical safe / sealed envelope)
- Policy going forward: secrets live in password manager + Abdul's head only — never in chat, email, Slack, code, or git history

### Step 15 — First repo + push verification
- Repository: `~/onchain/sandbox/hello_icp/`
- `git init` (re-init existed; `icp new` had already initialized one)
- `git add .` → 35 files staged, all expected (no node_modules / build artifacts leaked)
- `git commit -m "Initial commit: hello_icp scaffold from icp-cli"` → commit `587ac3e` on `main`
- GitHub repo created via web UI: `idunnomaan/hello_icp` (private)
- `git remote add origin git@github.com:idunnomaan/hello_icp.git`
- `git push -u origin main` → 48 objects (42.70 KiB) pushed at 6.10 MiB/s, branch tracking established
  - Note: GitHub repo originally created as `hello_ICP` (capital), renamed to lowercase post-push for convention consistency
  - Local remote URL updated via `git remote set-url origin git@github.com:idunnomaan/hello_icp.git`
- Status: COMPLETE — full git workflow verified end-to-end (commit → SSH auth → push → remote tracking)

---

## Convention notes (for future repos)

- Repo names: lowercase, words separated by underscores or hyphens (`hello_icp` not `hello_ICP`)
- Default branch: `main`
- Default visibility for sandbox/internal: Private. Public requires deliberate decision.
- First commit message format: `Initial commit: <project description>`
- One repo per project; never put unrelated projects in the same repo

---

## Identities & Accounts

| Item | Value |
|---|---|
| Project email (all sign-ups going forward) | `abdul.baasith16@gmail.com` |
| Personal email (storage full, deprecated for new sign-ups) | `abdulbaasyth16@gmail.com` |
| GitHub username | `idunnomaan` |
| GitHub commit email (noreply, use this in git config) | `283381541+idunnomaan@users.noreply.github.com` |
| Linux user (WSL Ubuntu) | `onchain_dev` |
| Linux hostname (WSL Ubuntu) | `AbdulBasith` |

---

## Notes

- Username/password chosen for Ubuntu: recorded locally by Abdul, not here
- This log is the source of truth for our setup. Future client deployments should follow the same pattern.

---

## The Practice — MVP QA Session (2026-05-22)

### Environment discoveries

| Discovery | Detail |
|---|---|
| II derives principal per origin (port included) | `localhost:5173` and `localhost:5174` yield different principals from the same passkey. Always standardise on one port. |
| Canonical dev port | 5173. Fixed via `server: { port: 5173, strictPort: true }` in `vite.config.ts`. |
| Abdul's local II principal (port 5173) | `ubo2q-4amlf-fq4xx-mlcpb-g7kyc-yqqzv-5cj4o-5ibmf-rz2ck-6fc36-oqe` |
| Fresh `icp network start` reassigns canister IDs | Stale network descriptor detected → cleaned → fresh IDs assigned sequentially. Always redeploy (not reinstall) after fresh start. |
| icp-cli flag | `--args` not `--argument` for passing init args to deploy |
| `icp canister id` doesn't exist | Use `find .icp/ -name "*.json" | xargs cat` to get canister IDs |

### Current canister state

| Item | Value |
|---|---|
| Backend canister ID | `t63gs-up777-77776-aaaba-cai` |
| Master controller principal | `ubo2q-4amlf-fq4xx-mlcpb-g7kyc-yqqzv-5cj4o-5ibmf-rz2ck-6fc36-oqe` |
| Deployed with | `icp deploy --args '(principal "ubo2q-...")'  backend` from `~/onchain/internal/the_practice` |

### QA pass results (all screens)

| Screen | Result | Notes |
|---|---|---|
| Dashboard | PASS | 8 stat cards render |
| Clients list | PASS | CLT-XXXX formatted IDs |
| Create Client | PASS | All fields persist to canister |
| Client Detail | PASS | CLT-XXXX reference shown |
| Client Edit | PASS | Identifier field added back |
| Matters list | PASS | Client ID shows as CLT-XXXX |
| Create Matter | PASS | FK validation working |
| Matter Detail | PASS | Status transitions, client link |
| Documents | PASS | Upload, file type validation, Download |
| Users | PASS | Add User form, self shown as Partner |
| Audit Log | PASS | Live, records every action |

### Frontend fixes applied this session

1. `vite.config.ts` — `port: 5173, strictPort: true` added
2. `ClientsPage.tsx` — `fmtClientId()` helper; ID column shows CLT-XXXX
3. `MattersPage.tsx` — `fmtClientId()` helper; Client ID column shows CLT-XXXX
4. `ClientDetailPage.tsx` — CLT-XXXX shown under client name; Identifier field added to edit form; identifier passed to `updateClient` (was hardcoded `null`)
