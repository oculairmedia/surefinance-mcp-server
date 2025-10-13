# Rollback Guide (Skeleton)

Use this if the Fast‑MCP migration needs to be reverted.

## Preconditions
- Branch: `feature/fast-mcp-migration`
- Tag: `pre-fast-mcp-YYYYMMDD`

## Steps
1. Stop containers
```
docker compose down
```
2. Return to checkpoint
```
git fetch --all --tags
git checkout pre-fast-mcp-YYYYMMDD
```
3. Rebuild and start
```
docker compose up -d --build
```
4. Verify legacy REST endpoints (temporary)
```
curl http://localhost:4332/tools/list
```

## Notes
- Update the date in the tag as appropriate.
- Document any data migrations separately (none expected for this migration).
