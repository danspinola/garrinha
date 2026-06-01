# NanoClaw — Project Rules

Personal AI assistant. See [README.md](../../README.md) for philosophy and setup. Architecture lives in `docs/`.

> This file mirrors the canonical project instructions in `CLAUDE.md` at the repository root. If they diverge, `CLAUDE.md` is the source of truth.

## Quick Context

The host is a single Node process that orchestrates per-session agent containers. Platform messages land via channel adapters, route through an entity model (users → messaging groups → agent groups → sessions), get written into the session's inbound DB, and wake a container. The agent-runner inside the container polls the DB, calls the LLM, and writes back to the outbound DB. The host polls the outbound DB and delivers through the same adapter.

**Everything is a message.** There is no IPC, no file watcher, no stdin piping between host and container. The two session DBs are the sole IO surface.

## Entity Model

```
users (id "<channel>:<handle>", kind, display_name)
user_roles (user_id, role, agent_group_id)       — owner | admin (global or scoped)
agent_group_members (user_id, agent_group_id)    — unprivileged access gate
user_dms (user_id, channel_type, messaging_group_id) — cold-DM cache

agent_groups (workspace, memory, CLAUDE.md, personality, container config)
    ↕ many-to-many via messaging_group_agents (session_mode, trigger_rules, priority)
messaging_groups (one chat/channel on one platform; unknown_sender_policy)

sessions (agent_group_id + messaging_group_id + thread_id → per-session container)
```

Privilege is user-level (owner/admin), not agent-group-level. See [docs/isolation-model.md](../../docs/isolation-model.md) for the three isolation levels.

## Two-DB Session Split

Each session has **two** SQLite files under `data/v2-sessions/<session_id>/`:

- `inbound.db` — host writes, container reads. `messages_in`, routing, destinations, pending_questions, processing_ack.
- `outbound.db` — container writes, host reads. `messages_out`, session_state.

Exactly one writer per file — no cross-mount lock contention. Heartbeat is a file touch at `/workspace/.heartbeat`, not a DB update. Host uses even `seq` numbers, container uses odd.

## Central DB

`data/v2.db` holds everything that isn't per-session: users, user_roles, agent_groups, messaging_groups, wiring, pending_approvals, user_dms, chat_sdk_*, schema_version. Migrations live at `src/db/migrations/`.

For ad-hoc queries, use: `pnpm exec tsx scripts/q.ts <db> "<sql>"`.

## Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Entry point: init DB, migrations, channel adapters, delivery polls, sweep, shutdown |
| `src/router.ts` | Inbound routing: messaging group → agent group → session → `inbound.db` → wake |
| `src/delivery.ts` | Polls `outbound.db`, delivers via adapter, handles system actions |
| `src/host-sweep.ts` | 60s sweep: `processing_ack` sync, stale detection, due-message wake, recurrence |
| `src/session-manager.ts` | Resolves sessions; opens `inbound.db` / `outbound.db`; manages heartbeat path |
| `src/container-runner.ts` | Spawns per-agent-group Docker containers with session DB + outbox mounts |
| `src/container-runtime.ts` | Runtime selection (Docker vs Apple containers), orphan cleanup |
| `src/db/` | DB layer — agent_groups, messaging_groups, sessions, container_configs, user_roles, migrations |
| `src/channels/` | Channel adapter infra (registry, Chat SDK bridge) |
| `src/providers/` | Host-side provider container-config |
| `container/agent-runner/src/` | Agent-runner: poll loop, formatter, provider abstraction, MCP tools |
| `container/skills/` | Container skills mounted into every agent session |
| `groups/<folder>/` | Per-agent-group filesystem (CLAUDE.md, skills, per-group overlay) |

## Development

```bash
# Host (Node + pnpm)
pnpm run dev          # Host with hot reload
pnpm run build        # Compile host TypeScript (src/)
./container/build.sh  # Rebuild agent container image (nanoclaw-agent:latest)
pnpm test             # Host tests (vitest)

# Agent-runner (Bun — separate package tree under container/agent-runner/)
cd container/agent-runner && bun install   # After editing agent-runner deps
cd container/agent-runner && bun test      # Container tests (bun:test)
```

## Container Runtime (Bun)

The agent container runs on **Bun**; the host runs on **Node** (pnpm). They communicate only via session DBs — no shared modules.

**Key gotchas:**

- Agent-runner deps: edit `package.json`, then `cd container/agent-runner && bun install` and commit `bun.lock`. Do not run `pnpm install` there.
- SQL in container: use `$name` in both SQL and JS keys (`.run({ $id: msg.id })`). `bun:sqlite` does not auto-strip the prefix.
- Tests in container: import from `bun:test`, not `vitest`.
- Session-DB pragmas: `journal_mode=DELETE` is load-bearing for cross-mount visibility.

## Supply Chain Security (pnpm)

- `minimumReleaseAge: 4320` (3 days) in `pnpm-workspace.yaml`
- Never add entries to `minimumReleaseAgeExclude` without human sign-off
- Never add packages to `onlyBuiltDependencies` without human approval
- Use `pnpm install --frozen-lockfile` in CI/automation/container builds

## Troubleshooting

| What | Where |
|------|-------|
| Host logs | `logs/nanoclaw.error.log` first, then `logs/nanoclaw.log` |
| Setup logs | `logs/setup.log` (overall), `logs/setup-steps/*.log` (per-step) |
| Session DBs | `data/v2-sessions/<agent-group>/<session>/` — `inbound.db` and `outbound.db` |

## Service Management

```bash
# macOS (launchd)
launchctl kickstart -k gui/$(id -u)/com.nanoclaw  # restart

# Linux (systemd)
systemctl --user restart nanoclaw

# Windows (PowerShell)
.\stop-nanoclaw.ps1
.\start-nanoclaw.ps1
```
