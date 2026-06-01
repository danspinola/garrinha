# Agent Instructions

This project includes coding-agent instructions in multiple formats so any AI assistant can understand the codebase:

| Agent | File |
|-------|------|
| Claude Code | `CLAUDE.md` (canonical source) |
| Amazon Q | `.amazonq/rules/nanoclaw.md` |
| Cursor | `.cursorrules` |
| Any agent | This file + `CLAUDE.md` |

## Quick Summary

NanoClaw is a personal AI assistant that runs agents in isolated Docker containers. Single Node.js host process orchestrates per-session containers communicating via SQLite message queues.

**Architecture:** `messaging apps → host (router) → inbound.db → container (Bun, Agent SDK) → outbound.db → host (delivery) → messaging apps`

**Key conventions:**

- Host runs on Node.js + pnpm; container runs on Bun
- Two SQLite files per session (inbound + outbound), one writer each
- Central DB at `data/v2.db` for users, groups, wiring
- Channel adapters and providers are skill-installed per fork
- Tests: `pnpm test` (host, vitest) / `bun test` (container, bun:test)

**For full project instructions**, read `CLAUDE.md` — it contains the complete entity model, key files reference, development commands, container gotchas, and troubleshooting guide. The name is a Claude Code convention but the content is agent-agnostic.
