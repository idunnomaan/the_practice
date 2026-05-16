# L1 Identity — Specification

> Spec date: 2026-05-16
> Designed in: Cowork
> Implements: the foundation of the five-layer architecture (see AGENTS.md §4)
> Source of truth for Claude Code. Any ambiguity not resolved here → ask Abdul in Cowork before coding.

---

## 1. Purpose

L1 owns the canister's authorization model. It is the only layer that decides "who is allowed to do what." Everything in L2, L4, etc. will call into L1's role-check helpers — not duplicate them.

L1 manages three distinct identity concepts:

1. **Master controller principal** — the firm's senior partner. Highest authority. Held by the client.
2. **Operations principal** — Onchain Inc.'s ops account. Revocable. Can perform a narrow set of canister-management actions but cannot touch user data or roles.
3. **User roles** — `Partner | Associate | Staff`. Day-to-day app users.

These three are independent dimensions. The master controller is also auto-registered as a Partner (so they can use the app), but the operations principal is NOT registered as any user role.

L5 (Audit) does not exist yet. Implementer must call an internal `audit(actor: Principal, action: Text, target: ?Principal)` stub on every state-changing operation. For now it's a no-op with a `// TODO L5: wire to audit log` comment. When L5 lands, only that stub changes.

---

## 2. Locked decisions

| # | Decision | Source |
|---|---|---|
| Q1 | Master controller principal is a **required init argument**. No default. | Cowork 2026-05-16 |
| Q2 | Operations principal is **NOT set at install**. Master controller grants it post-install via `grantOperations(principal)`. | Cowork 2026-05-16 |
| Q3 | Role hierarchy: **Partner ⊃ Associate ⊃ Staff**. Each role automatically satisfies any check for a lower role. | Cowork 2026-05-16 |
| — | One principal per user. Multi-device support deferred. | Cowork 2026-05-16 |
| — | Master controller principal is **auto-registered as a Partner** at install (so the deploying firm can use the app immediately). | Cowork 2026-05-16 |
| — | Operations principal holds **no user role** — manages canister-level controls only. | Cowork 2026-05-16 |

---

## 3. Data model

```motoko
public type Role = {
  #Partner;
  #Associate;
  #Staff;
};

public type UserRecord = {
  role: Role;
  addedBy: Principal;    // who registered this user (audit lineage)
  addedAt: Time.Time;    // nanoseconds since epoch
  suspended: Bool;       // F-08 toggles this; default false
};
```

State (as fields on the `persistent actor`):
- `masterController : Principal` — set at install, mutated only by `transferMasterController`
- `operationsPrincipal : ?Principal` — null until granted, nullable after revoke
- `users : Map.Map<Principal, UserRecord>` — registry of all app users

Use `mo:core/pure/Map` keyed by `Principal` with `Principal.compare` as the ordering function. The `persistent actor` declaration handles persistence automatically — no StableBTreeMap, no manual `pre_upgrade`/`post_upgrade` hooks (per the `stable-memory` skill).

---

## 4. Public interface

### 4.1 Queries (read-only, ~200ms, NOT consensus-verified)

| Method | Caller required | Returns | Behavior |
|---|---|---|---|
| `whoAmI()` | none | `Principal` | Returns `msg.caller`. Debug helper. |
| `getMyRole()` | none | `?Role` | Caller's role, or `null` if not registered or suspended. |
| `getMasterController()` | none | `Principal` | Always non-null after install. |
| `getOperationsPrincipal()` | none | `?Principal` | Null until granted. |
| `getUserCount()` | Partner | `Nat` | Total registered users including master controller. Traps if caller not Partner. |
| `listUsers()` | Partner | `[(Principal, UserRecord)]` | Full user registry. Traps if caller not Partner. (F-08 needs this.) |

### 4.2 Updates (write, ~2s, consensus-verified)

Every update method below MUST:
1. Reject anonymous principal (`Principal.isAnonymous(msg.caller)`)
2. Perform its role check
3. Call `audit(msg.caller, "<methodName>", ?target)` before returning

| Method | Caller required | Args | Behavior |
|---|---|---|---|
| `grantOperations` | Master controller | `Principal` | Sets `operationsPrincipal = ?p`. Traps if `operationsPrincipal` already non-null (must revoke first). Traps if `p` is anonymous, equals master controller, or equals a registered user. |
| `revokeOperations` | Master controller | `()` | Sets `operationsPrincipal = null`. Idempotent — succeeds if already null. |
| `transferMasterController` | Master controller | `Principal` | Replaces master controller. `p` MUST already be a registered Partner. Old master controller stays as Partner (NOT auto-removed). Traps if `p` is anonymous, equals operations principal, or is not a registered Partner. |
| `addUser` | Partner | `Principal, Role` | Registers a new user. Traps if anonymous, already registered, or equals operations principal. |
| `setUserRole` | Partner | `Principal, Role` | Changes existing user's role. Traps if user not found. Cannot change the master controller's role (must transfer first). |
| `suspendUser` | Partner | `Principal` | Sets `suspended = true`. Suspended users fail all role checks. Cannot suspend the master controller. |
| `unsuspendUser` | Partner | `Principal` | Sets `suspended = false`. |
| `removeUser` | Partner | `Principal` | Deletes the user record. Cannot remove the master controller (must transfer first). |

### 4.3 Internal helpers (Motoko-only, not in Candid)

| Helper | Behavior |
|---|---|
| `requireAuthenticated(caller)` | Traps if `Principal.isAnonymous(caller)`. |
| `requireMasterController(caller)` | Traps if `caller != masterController`. Anonymous already rejected by the first check. |
| `requireRole(caller, minRole)` | Traps if caller is unregistered, suspended, or has a role strictly lower than `minRole` in the hierarchy. Partner satisfies any check; Associate satisfies Associate/Staff; Staff only satisfies Staff. |
| `requireOperationsOrMaster(caller)` | Traps unless caller is master controller OR operations principal. Reserved for L1-level ops calls (none use it yet; future: cycles top-ups, settings updates). |
| `audit(actor, action, target)` | **Stub for now.** No-op + `// TODO L5: wire to audit log` comment. L5 will replace the body. |

---

## 5. Initialization

Canister installs with one argument:

```motoko
shared(installer) persistent actor class TheTracticePersistent(
  masterControllerArg: Principal
) = this {
  // ...
}
```

At install time:
1. `assert(not Principal.isAnonymous(masterControllerArg))` — trap install if anonymous
2. `masterController := masterControllerArg`
3. `operationsPrincipal := null`
4. `users := Map.empty()`, then add master controller with `{ role = #Partner; addedBy = installer.caller; addedAt = Time.now(); suspended = false }`

`installer.caller` is the deployer (icp-cli identity). It's not stored as state — only used to record who installed the canister in the master controller's `UserRecord.addedBy` field for audit lineage.

### Local deploy script

Create `scripts/deploy-local.sh` (executable) that auto-fills the deployer's principal:

```bash
#!/usr/bin/env bash
set -euo pipefail
DEPLOYER=$(icp identity principal)
echo "Installing the_practice with master controller = $DEPLOYER"
icp deploy --argument "(principal \"$DEPLOYER\")"
```

For mainnet deploy, the firm's principal is passed manually with their consent — never scripted.

---

## 6. Security invariants

The implementation must guarantee these. Add comments naming them next to the relevant code.

1. **Anonymous principal cannot hold any identity** (master controller, operations, or user role). Rejected at every entry point.
2. **Master controller is always a registered Partner** while installed. The only way it stops being a registered user is `transferMasterController` (which re-registers the new one and leaves the old one as Partner).
3. **Operations principal can never appear in the `users` registry.** Enforced in `grantOperations` and `addUser`.
4. **Suspension blocks role checks for any role**, even Partner.
5. **`setUserRole` cannot elevate the caller's own role** — only Partners can call it, and the existing Partner-only guard already prevents Staff/Associate self-promotion.
6. **No method uses `canister_inspect_message` as a security boundary.** All checks are duplicated inside method bodies. (`canister-security` skill, pitfall #1.)
7. **`pre_upgrade` must not trap.** Use the `persistent actor` declaration (automatic stable variables) — no manual serialization. (`canister-security` skill, pitfall #4.)

---

## 7. Acceptance criteria — what "L1 done" means

The implementer must verify all of these locally before reporting done.

1. `icp build` succeeds with no errors or warnings.
2. `mops test` runs (even with zero tests — confirms toolchain). Optionally: implementer adds unit tests for `requireRole` hierarchy logic.
3. `icp deploy` (or `./scripts/deploy-local.sh`) succeeds.
4. Candid UI at the printed backend URL shows all listed query and update methods with correct signatures.
5. `scripts/smoke-l1.sh` runs and passes. It must:
   - Install the canister via `deploy-local.sh`
   - Confirm `whoAmI()` returns the deployer's principal
   - Confirm `getMyRole()` returns `(opt variant { Partner })` for the master controller
   - Confirm `getMasterController()` returns the deployer's principal
   - Confirm `getOperationsPrincipal()` returns `(null)`
   - Confirm calling `getUserCount()` returns `(1 : nat)`
   - Use `icp canister call` to exercise at least: `grantOperations`, `revokeOperations`, `addUser`, `setUserRole`, `suspendUser`, `getMyRole` for the newly-added user
   - Document each step with `echo` lines explaining what's being tested

The smoke script may use `icp identity new --silent` to spin up additional test identities and switch with `icp identity default`.

---

## 8. Files to create or modify

| File | Action |
|---|---|
| `backend/src/main.mo` | Replace placeholder `greet` actor with the L1 actor class. |
| `backend/src/Types.mo` | Create. Define `Role`, `UserRecord`. |
| `backend/src/Auth.mo` | Create (optional but recommended for readability). Hold `requireXxx` helpers. |
| `backend/mops.toml` | Add `core = "2.0.0"` to `[dependencies]` if not present. |
| `backend/canister.yaml` | No changes (recipe already correct). |
| `icp.yaml` | Add `ii: true` under `networks.local` so II becomes available locally (we don't wire frontend yet — but local II availability lets the smoke test use II-issued principals if desired). |
| `scripts/deploy-local.sh` | Create (executable). |
| `scripts/smoke-l1.sh` | Create (executable). |
| `frontend/` | Do NOT modify. Frontend integration is later. |
| `AGENTS.md`, `CLAUDE.md` | Do NOT modify. |

---

## 9. Skills the implementer MUST fetch before writing code

In this order:

1. `https://skills.internetcomputer.org/skills/motoko/SKILL.md` — Motoko syntax, `persistent actor` declaration, `mo:core` standard library APIs, common compiler errors. Critical for correct syntax.
2. `https://skills.internetcomputer.org/skills/stable-memory/SKILL.md` — confirm `persistent actor` + `Map.Map` storage handles upgrades correctly. Verify no manual `pre_upgrade`/`post_upgrade` is needed for this layer.
3. `https://skills.internetcomputer.org/skills/canister-security/SKILL.md` — already designed against this; verify the `requireAuthenticated` / `requireRole` pattern matches the skill's current Motoko example.
4. `https://skills.internetcomputer.org/skills/mops-cli/SKILL.md` — for adding `core` dependency and any setup needed.

If any skill reveals a contradiction with this spec, STOP and report it back to Abdul before coding around it. The spec may be wrong; we want to fix it once rather than diverge silently.

---

## 10. Out of scope for L1

Do NOT implement any of these in L1. Each has its own layer or phase.

- Frontend Internet Identity AuthClient wiring (frontend phase, after L4)
- Audit log emission (L5) — the `audit(...)` stub is fine for now
- Per-matter access control (L4)
- Per-document access control (L4)
- Multi-device principal aggregation (deferred)
- Cycles top-ups / canister settings (later, will use `requireOperationsOrMaster`)
- F-07 export functionality (L4)
- Mainnet deploy (Studio Stage 4)

---

## 11. When you (Claude Code) think you're done

Before reporting "L1 complete," run this checklist:

1. [ ] All 7 security invariants in §6 are enforceable from code (add a comment naming each one where it's enforced).
2. [ ] All acceptance criteria in §7 pass.
3. [ ] No files in `frontend/` were modified.
4. [ ] `AGENTS.md` and `CLAUDE.md` are untouched.
5. [ ] You called the relevant skill BEFORE writing any code (and you remembered what each skill said).
6. [ ] The diff is reasonable in size (<800 LOC). If it's larger, you probably over-engineered something — pause and ask.

Then report: list of files changed, line counts, one-paragraph summary of the smoke test output, and any decisions you made that weren't in this spec (we'll review them in Cowork).

---

*This spec is locked. If you find a real ambiguity, stop and ask Abdul. Don't improvise.*
