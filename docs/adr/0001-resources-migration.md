# ADR 0001: Resources Migration Strategy (Skeleton)

## Status
Proposed

## Context
Current server exposes `/resources` via a custom registry/handler. Fast‑MCP focuses on tools (and may support a resource concept). We need to decide to migrate or remove.

## Options
1. Migrate to FastMcp::Resource (or equivalent abstraction)
2. Remove resources to simplify the surface area

## Decision
TBD

## Consequences
- If migrate: maintain feature parity; additional maintenance cost
- If remove: smaller API; verify no clients depend on `/resources`

## Implementation Notes
- Inventory current resources and consumers
- If kept, define registration and resolution path in server init
- If removed, delete `lib/surefinance_mcp/resources/*` and update docs
