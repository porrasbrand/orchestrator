# Phase 01: Worker Registry

## Context
You are working on the **orchestrator** project at `~/projects/orchestrator/` on worker-1.

## Prior Work Summary
Sprints 1-3 complete. The orchestrator now has: structured learnings (JSONL), context handoff, spec quality pre-check, diff-based verification, structured result.json, executable smoke tests, cancellation mechanism, and phase idempotency. All scripts use SSH key auth with retry.

Currently, worker connection details are hardcoded in `scripts/verify.sh` (lines with `if [ "$WORKER" = "worker-1" ]` / `elif [ "$WORKER" = "worker-2" ]`). Adding a third worker means editing verify.sh directly. This doesn't scale.

## Objective
Create a `config/workers.json` registry file and update verify.sh to read worker SSH details from it instead of hardcoded if/else blocks. Other scripts that need worker info can also read from this file.

## Implementation Steps

1. **Create `config/workers.json`** with this schema:
   ```json
   {
     "workers": {
       "worker-1": {
         "host": "worker-1.example.internal",
         "port": 22,
         "user": "deploy",
         "ssh_key": "~/.ssh/id_worker_ed25519",
         "base_path": "~/projects",
         "capabilities": ["node", "python", "git", "jq"],
         "status": "active"
       },
       "worker-2": {
         "host": "worker-2.example.internal",
         "port": 2200,
         "user": "deploy",
         "ssh_key": "~/.ssh/id_worker_ed25519",
         "base_path": "~/projects",
         "capabilities": ["node", "python", "git", "jq"],
         "status": "active"
       }
     }
   }
   ```

2. **Create `scripts/get-worker.sh`** — A helper that reads worker config:
   ```
   Usage: get-worker.sh <worker-name> <field>
   Example: get-worker.sh worker-1 host → worker-1.example.internal
   Example: get-worker.sh worker-1 ssh_cmd → ssh -i ~/.ssh/id_worker_ed25519 worker-1.example.internal -p 22 -l deploy -o ConnectTimeout=10 -o BatchMode=yes
   ```
   Special field `ssh_cmd` constructs the full SSH command from host/port/user/ssh_key.
   Special field `scp_cmd` constructs the SCP command prefix.
   Uses `jq` to read config/workers.json.

3. **Modify `scripts/verify.sh`** — Replace the hardcoded worker if/else block with a call to get-worker.sh:
   - Instead of: `if [ "$WORKER" = "worker-1" ]; then SSH_CMD="..."; REMOTE_BASE="..."`
   - Use: `SSH_CMD=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" ssh_cmd)` and `REMOTE_BASE=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" base_path)`
   - Keep the `ssh_retry` function as-is (it uses $SSH_CMD)
   - If worker not found in registry, print error and exit 1

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 4 item 4.1 as done.

## Files to Create
- `config/workers.json` — Worker registry
- `scripts/get-worker.sh` — Worker config reader (make executable)

## Files to Modify
- `scripts/verify.sh` — Replace hardcoded worker config with get-worker.sh calls
- `ENHANCEMENT-ROADMAP.md` — Mark 4.1 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/check-spec.sh`, `scripts/cancel-task.sh`
- `templates/`

## Expected Files Changed
- `config/workers.json` (create)
- `scripts/get-worker.sh` (create)
- `scripts/verify.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/01-worker-registry/result.md` (create)
- `.planning/phases/01-worker-registry/result.json` (create)

## Acceptance Criteria
- [ ] `config/workers.json` exists with worker-1 and worker-2 worker definitions
- [ ] `scripts/get-worker.sh` is executable and returns correct fields for both workers
- [ ] `get-worker.sh worker-1 host` returns `worker-1.example.internal`
- [ ] `get-worker.sh worker-1 ssh_cmd` returns a valid SSH command string
- [ ] `get-worker.sh unknown-worker host` exits with error
- [ ] verify.sh uses get-worker.sh instead of hardcoded if/else
- [ ] verify.sh still works for worker "worker-1" (same behavior as before)
- [ ] ENHANCEMENT-ROADMAP.md shows 4.1 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -f ~/projects/orchestrator/config/workers.json && echo EXISTS` → expect `EXISTS`
2. `test -x ~/projects/orchestrator/scripts/get-worker.sh && echo EXECUTABLE` → expect `EXECUTABLE`
3. `bash ~/projects/orchestrator/scripts/get-worker.sh worker-1 host` → expect `worker-1.example.internal`
4. `bash ~/projects/orchestrator/scripts/get-worker.sh worker-2 port` → expect `2200`
5. `bash ~/projects/orchestrator/scripts/get-worker.sh worker-1 ssh_cmd | grep -c "worker-1.example.internal"` → expect `1`
6. `bash ~/projects/orchestrator/scripts/get-worker.sh nonexistent host 2>&1; echo "EXIT:$?"` → expect `EXIT:1`
7. `grep "get-worker" ~/projects/orchestrator/scripts/verify.sh | head -1` → expect match
8. `grep "4.1" ~/projects/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/01-worker-registry/result.md`
4. Commit with prefix: `[orchestrator-sprint4-01]`
5. Do NOT push
