# Phase 01: Worker Registry

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprints 1-3 complete. The orchestrator now has: structured learnings (JSONL), context handoff, spec quality pre-check, diff-based verification, structured result.json, executable smoke tests, cancellation mechanism, and phase idempotency. All scripts use SSH key auth with retry.

Currently, worker connection details are hardcoded in `scripts/verify.sh` (lines with `if [ "$WORKER" = "hetzner" ]` / `elif [ "$WORKER" = "wsl2" ]`). Adding a third worker means editing verify.sh directly. This doesn't scale.

## Objective
Create a `config/workers.json` registry file and update verify.sh to read worker SSH details from it instead of hardcoded if/else blocks. Other scripts that need worker info can also read from this file.

## Implementation Steps

1. **Create `config/workers.json`** with this schema:
   ```json
   {
     "workers": {
       "hetzner": {
         "host": "remote.manuelporras.com",
         "port": 22,
         "user": "ubuntu",
         "ssh_key": "~/.ssh/id_remote_claude",
         "base_path": "~/awsc-new/awesome",
         "capabilities": ["node", "python", "git", "jq"],
         "status": "active"
       },
       "wsl2": {
         "host": "ssh.manuelporras.com",
         "port": 2222,
         "user": "ubuntu",
         "ssh_key": "~/.ssh/id_remote_claude",
         "base_path": "~/awsc-new/awesome",
         "capabilities": ["node", "python", "git", "jq"],
         "status": "active"
       }
     }
   }
   ```

2. **Create `scripts/get-worker.sh`** — A helper that reads worker config:
   ```
   Usage: get-worker.sh <worker-name> <field>
   Example: get-worker.sh hetzner host → remote.manuelporras.com
   Example: get-worker.sh hetzner ssh_cmd → ssh -i ~/.ssh/id_remote_claude remote.manuelporras.com -p 22 -l ubuntu -o ConnectTimeout=10 -o BatchMode=yes
   ```
   Special field `ssh_cmd` constructs the full SSH command from host/port/user/ssh_key.
   Special field `scp_cmd` constructs the SCP command prefix.
   Uses `jq` to read config/workers.json.

3. **Modify `scripts/verify.sh`** — Replace the hardcoded worker if/else block with a call to get-worker.sh:
   - Instead of: `if [ "$WORKER" = "hetzner" ]; then SSH_CMD="..."; REMOTE_BASE="..."`
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
- [ ] `config/workers.json` exists with hetzner and wsl2 worker definitions
- [ ] `scripts/get-worker.sh` is executable and returns correct fields for both workers
- [ ] `get-worker.sh hetzner host` returns `remote.manuelporras.com`
- [ ] `get-worker.sh hetzner ssh_cmd` returns a valid SSH command string
- [ ] `get-worker.sh unknown-worker host` exits with error
- [ ] verify.sh uses get-worker.sh instead of hardcoded if/else
- [ ] verify.sh still works for worker "hetzner" (same behavior as before)
- [ ] ENHANCEMENT-ROADMAP.md shows 4.1 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -f ~/awsc-new/awesome/orchestrator/config/workers.json && echo EXISTS` → expect `EXISTS`
2. `test -x ~/awsc-new/awesome/orchestrator/scripts/get-worker.sh && echo EXECUTABLE` → expect `EXECUTABLE`
3. `bash ~/awsc-new/awesome/orchestrator/scripts/get-worker.sh hetzner host` → expect `remote.manuelporras.com`
4. `bash ~/awsc-new/awesome/orchestrator/scripts/get-worker.sh wsl2 port` → expect `2222`
5. `bash ~/awsc-new/awesome/orchestrator/scripts/get-worker.sh hetzner ssh_cmd | grep -c "remote.manuelporras.com"` → expect `1`
6. `bash ~/awsc-new/awesome/orchestrator/scripts/get-worker.sh nonexistent host 2>&1; echo "EXIT:$?"` → expect `EXIT:1`
7. `grep "get-worker" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | head -1` → expect match
8. `grep "4.1" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/01-worker-registry/result.md`
4. Commit with prefix: `[orchestrator-sprint4-01]`
5. Do NOT push
