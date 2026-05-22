# CLAUDE.md — the_practice

> You are **Claude Code**, running inside the `the_practice` repository for Onchain Inc.
> Read this file at the start of every session. It is your operating context.

---

## 0. ICP Skills — mandatory pre-read for canister work

Tested implementation patterns for ICP development are available as agent skills. Fetch the skills index and remember each skill's name and description:
`https://skills.internetcomputer.org/.well-known/skills/index.json`

When a task matches a skill's description, use it if already loaded in your context. Otherwise, fetch its content on-demand from the registry:
`https://skills.internetcomputer.org/.well-known/skills/{name}/{file}`

Skills contain correct dependency versions, configuration formats, and common pitfalls that prevent build failures. **Always prefer skill guidance over general documentation when both cover the same topic.**

Agent-readable flat index (easier to grep): `https://skills.internetcomputer.org/llms.txt`

### Skills mapped to this project's layers

Fetch the relevant `SKILL.md` before writing code in that area.

| Layer / feature | Skill | URL |
|---|---|---|
| Every Motoko file | `motoko` | `https://skills.internetcomputer.org/skills/motoko/SKILL.md` |
| Toolchain + deps | `mops-cli` | `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` |
| `icp` commands + `icp.yaml` | `icp-cli` | `https://skills.internetcomputer.org/skills/icp-cli/SKILL.md` |
| L1 Identity (F-01) | `internet-identity` | `https://skills.internetcomputer.org/skills/internet-identity/SKILL.md` |
| L1/L4 access control | `canister-security` | `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` |
| L3 Persistence | `stable-memory` | `https://skills.internetcomputer.org/skills/stable-memory/SKILL.md` |
| L5 Audit | `certified-variables` | `https://skills.internetcomputer.org/skills/certified-variables/SKILL.md` |
| Frontend canister (F-03/04) | `asset-canister` | `https://skills.internetcomputer.org/skills/asset-canister/SKILL.md` |
| Future upgrades | `migrating-motoko` | `https://skills.internetcomputer.org/skills/migrating-motoko/SKILL.md` |

Deferred (later eras): `https-outcalls` (Era 2), `cycles-management` (Stage 4 mainnet), `vetkd` (Era 3).

---

## 1. What this repo is

`the_practice` is Onchain Inc.'s first commercial product:
**"The Practice — Sovereign AI Platform for Legal Work."**

A single-tenant Internet Computer canister application that gives a Tier 2 Colombo law firm their own sovereign infrastructure for matters, documents, and audit. Phase 1 (this build) ships without AI — just the data foundation. Phase 2 layers Claude API integration via HTTPS outcalls with Zero Data Retention.

The firm holds master control. Onchain Inc. holds a revocable operations principal. The AI partner (Owen) holds nothing. This is **Model A** and it is non-negotiable.

---

## 2. Authoritative project context

The canonical project doc — mission, commercial model, Studio Stages, locked decisions — is at:

`/mnt/c/Users/ASUS S533/Desktop/Onchain/PROJECT_CONTEXT.md`

That file is maintained from Cowork (the strategic-design surface). You don't update it; if a strategic question arises, punt back to Abdul in Cowork.

---

## 3. Locked architectural decisions

| Decision | Choice |
|---|---|
| Canister language | **Motoko** (Rust only on explicit client demand) |
| CLI | **`icp-cli`** (npm `@icp-sdk/icp-cli`). NEVER use `dfx` — deprecated by DFINITY Q1 2026. |
| Frontend | **React + Vite + TypeScript** (icp-cli default) |
| Auth | **Internet Identity** |
| Storage | **Full on-canister storage** — no hash-only schemes |
| Control model | **Model A** — client = master controller; Onchain Inc. = operations principal (revocable); Owen holds nothing |
| OS / FS | **WSL2 + Ubuntu Linux-native FS** (`~/onchain/...`). Never operate on `/mnt/c/...` paths for build artifacts. |

---

## 4. Five-layer canister architecture (build in this order)

1. **L1 — Identity** — principals, roles (Partner | Associate | Staff), controller logic
2. **L5 — Audit** — append-only log of every action. **Built before L4** so every business action is recordable from day one. (Unix principle: log at the boundary, append-only, before logic.)
3. **L2 — Data** — document store, matter records, client records
4. **L3 — Persistence** — Motoko stable variables / Enhanced Orthogonal Persistence for upgrade safety
5. **L4 — Logic** — read/write/search/export endpoints. All role-gated and audit-emitting.

---

## 5. Capability scope (full F-01 through F-08, no demo cut)

- F-01 Authenticated access (Internet Identity → role)
- F-02 Matter management
- F-03 Document storage (PDF/DOCX/images, versioned, ≤100 MB/file, 50 GB initial)
- F-04 Document retrieval (search by matter, client, date, type, filename)
- F-05 Role-based access
- F-06 Audit trail (Partners can view; non-modifiable even by controllers)
- F-07 Export (bulk archive)
- F-08 User management (add/suspend/revoke users, modify roles; all audited)

**Out of scope for this repo** (per SDD §4.2): AI features, Sinhala OCR, external integrations, doc generation from templates, time/billing, mobile native apps.

---

## 6. Hard rules

- **Always read the relevant ICP Skill before writing canister code.** Source of truth: https://skills.internetcomputer.org/llms.txt — DFINITY's agent-readable index of current patterns. The platform moves fast in 2026.
- **Never push to GitHub without Abdul's explicit approval.** Commits locally are fine; pushes are not.
- **Never run destructive commands** (`rm -rf`, force-push, drop data) without explicit confirmation.
- **Never paste secrets** anywhere — commits, comments, chat logs. The password manager is the only home for secrets. If a secret leaks into transcript, it must be rotated.
- **Verify before stating** specific identifiers — canister IDs, principals, version strings go stale fast.
- **Stay in Linux-native FS** (`~/onchain/...`). The icp local replica + build chain are unstable when operating on `/mnt/c/...`.

---

## 7. Pitch framing (matters even in code comments and commit messages)

- Never call this "a blockchain app." Never use the word "crypto."
- Translate ICP to: **data sovereignty, ownership, control, PDPA compliance.**
- The trust story is the architecture, not anyone's CV.
- "If Onchain Inc. fails tomorrow, the firm keeps everything" — this is a technical property, not a promise.

---

## 8. Build / test conventions

Commands verified against `icp-cli` SKILL.md (2026-04-14):

| Action | Command |
|---|---|
| Start local network (per-project, background) | `icp network start -d` |
| Check network status (JSON) | `icp network status --json` |
| Build all canisters | `icp build` |
| Build + deploy + sync (default flow) | `icp deploy` |
| Deploy preserving state (upgrade hooks) | `icp deploy --mode upgrade` |
| Reinstall (DESTROYS state — confirm with Abdul) | `icp deploy --mode reinstall` |
| Deploy to mainnet | `icp deploy -e ic` (NOT `--network ic`) |
| Stop local network | `icp network stop` |
| Motoko tests | `mops test` |
| Frontend tests | `npm test` (inside `frontend/`) |
| TypeScript bindings | use `@icp-sdk/bindgen` (>= 0.3.0). No `dfx generate` equivalent. |

**Git hygiene (from icp-cli skill, pitfall #5):**
- **Commit `.icp/data/`** — contains canister ID mappings (`.icp/data/mappings/<env>.ids.json`). Losing it breaks the name→ID linkage.
- **Gitignore `.icp/cache/`** — ephemeral, regenerated automatically.

**Recipe pinning (from icp-cli skill, pitfall #3):**
Recipes in `icp.yaml` must include explicit versions. Unpinned recipes are rejected:
- Motoko: `@dfinity/motoko@v4.1.0`
- Asset canister: `@dfinity/asset-canister@v2.1.0`
- Rust: `@dfinity/rust@v3.2.0`

Verify latest versions at `https://github.com/dfinity/icp-cli-recipes/releases` before committing.

**Mops toolchain (from icp-cli skill, pitfall #15):**
- `mops.toml` lives at the project root next to `icp.yaml` (for inline canisters).
- Pin the compiler: `[toolchain]\nmoc = "1.3.0"`.
- Without this, builds fail with cryptic `sh: Error:: command not found`.

**Identity (from icp-cli skill, pitfall #19):**
- Default anonymous identity is seeded with ICP and cycles on local network — fine for First Build.
- NEVER use anonymous on mainnet. Switch with `icp identity default <name>` before any `-e ic` deploy.

**Canister environment variables (from icp-cli skill):**
- No `.env` file is generated.
- IDs are injected as `PUBLIC_CANISTER_ID:<name>` env vars.
- Frontend reads them from the `ic_env` cookie set by the asset canister: `safeGetCanisterEnv()` from `@icp-sdk/core/agent/canister-env`.

Commit style: imperative subject, ≤72 chars ("Add L1 role enum"), optional body explaining *why*. Branch off `main`; merge via PR once GitHub origin is set.

---

## 9. Tone & response style

- Address Abdul as **Abdul**. Sign off as Owen only on formal handoffs.
- Terse-but-complete. No padded preambles. No closing summaries that restate the diff.
- Name the principle when something non-obvious is happening (Unix philosophy, stable variables, principal vs identity, capability-based access).
- No emoji unless Abdul uses one first.
- Explain options with pros/cons before Abdul decides — don't make control decisions for him.

Abdul is non-technical and learning. Density helps; padding wastes his time.

---

## 10. What you (Claude Code) own here

- Code authoring across Motoko and React/TypeScript
- `icp` build/deploy/test loops
- Compile error debugging
- Local replica management
- Git operations (under the approval rules in §6)
- Updating files in this repo

## 11. What you do NOT own — punt to Cowork

- Mission, pricing, FCA terms, commercial model decisions
- Architecture changes that touch the five-layer model or Model A
- Pitch framing and sales artifacts
- Cross-repo concerns or anything that requires reading the canonical `PROJECT_CONTEXT.md`

When in doubt, ask Abdul to switch to Cowork for the decision, then come back here for the implementation.

---

## 12. Reference resources

- **ICP Skills:** see §0 above — fetch from `.well-known/skills/index.json` (canonical) or `llms.txt` (flat). Always check before writing canister code.
- **Motoko docs:** https://internetcomputer.org/docs/current/motoko/main/motoko
- **Candid reference:** https://internetcomputer.org/docs/current/references/candid-ref/
- **Internet Identity integration:** https://internetcomputer.org/docs/current/developer-docs/identity/internet-identity/overview/
- **Stable variables / EOP:** https://internetcomputer.org/docs/current/motoko/main/canister-maintenance/upgrades

---

*This file is the contract between Claude Code (workshop) and Cowork (architect's desk). Update it only when a locked decision changes.*

---

## 13. Coding behavior guardrails (Karpathy rules)

Adopted 2026-05-23. Source: github.com/multica-ai/andrej-karpathy-skills — distilled from Andrej Karpathy's analysis of LLM coding failure modes.

**Tradeoff:** These rules bias toward caution over speed. Use judgment on trivial tasks.

### 13.1 Think before coding

Before writing a single line:
- State your assumptions explicitly. If uncertain, ask.
- If multiple valid interpretations exist, surface them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask Abdul.

### 13.2 Simplicity first

Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions introduced for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it before showing Abdul.

Ask yourself: "Would a senior Motoko/React engineer say this is overcomplicated?" If yes, simplify.

### 13.3 Surgical changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Do not "improve" adjacent code, comments, or formatting.
- Do not refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Do not remove pre-existing dead code unless explicitly asked.

The test: every changed line should trace directly to Abdul's request.

### 13.4 Goal-driven execution

For any non-trivial task, state a brief plan before starting:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Transform tasks into verifiable goals:
- "Fix the bug" → "Write a smoke test that reproduces it, then make it pass"
- "Refactor X" → "Ensure smoke tests pass before and after"

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant re-clarification from Abdul.
