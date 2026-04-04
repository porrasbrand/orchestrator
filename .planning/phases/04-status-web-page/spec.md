# Phase 04: Status Web Page

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 4 progress:
- **Phase 01 (worker-registry):** `config/workers.json` + `scripts/get-worker.sh`. verify.sh reads from registry.
- **Phase 02 (dependency-dag):** `scripts/dag.sh` analyzes dependencies, shows parallel groups and ready phases.
- **Phase 03 (branch-per-phase):** `scripts/branch.sh` with create/merge/list subcommands for phase branches.

Currently, orchestration progress is only visible via `scripts/status.sh` in the terminal. There's no way to check progress from a phone, share a link, or get a visual overview. A self-contained HTML dashboard solves this.

## Objective
Create `scripts/generate-status-page.sh` that reads `.planning/status.json` and `.planning/events.jsonl` and generates a self-contained HTML file showing orchestration progress visually.

## Implementation Steps

1. **Create `scripts/generate-status-page.sh`**:
   ```
   Usage: generate-status-page.sh <project-path> [output-file]
   Default output: <project-path>/.planning/status.html
   ```

2. **The HTML page should include (all inline, no external deps):**

   **Header:**
   - Project name (from status.json)
   - Status badge (in-progress / complete / blocked)
   - Progress bar (phases_complete / phases_total)
   - Started at / Last updated timestamps

   **Phase Table:**
   - Each phase as a row: name, status (with color), commit hash, smoke tests (pass/total), revisions, timing
   - Status colors: complete=green, queued=yellow, pending=gray, failed=red, cancelled=orange
   - Current phase highlighted

   **Event Timeline:**
   - Last 20 events from events.jsonl displayed as a timeline
   - Each event shows: timestamp, event type, phase name
   - Color-coded by event type

   **Summary Stats:**
   - Total phases, complete, revisions, smoke tests passed
   - Wall-clock time (from first to last event timestamp)

3. **Styling:** Clean, minimal CSS inline in `<style>` tag. Dark or light theme. Mobile-friendly (simple responsive). Monospace font for data. No JavaScript required (pure HTML+CSS).

4. **The script should use `jq` for JSON parsing** and generate HTML via heredoc/echo. Keep it simple — bash + jq, no node required.

5. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 4 item 4.4 as done.

## Files to Create
- `scripts/generate-status-page.sh` — HTML generator (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 4.4 as done

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/generate-status-page.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/04-status-web-page/result.md` (create)
- `.planning/phases/04-status-web-page/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/generate-status-page.sh` is executable
- [ ] Generates valid HTML file from status.json + events.jsonl
- [ ] HTML is self-contained (inline CSS, no external dependencies)
- [ ] Shows project name, status, progress bar
- [ ] Shows phase table with status colors
- [ ] Shows event timeline (last 20 events)
- [ ] Shows summary stats
- [ ] Works with current Sprint 4 orchestration data
- [ ] Output file is readable in a browser
- [ ] ENHANCEMENT-ROADMAP.md shows 4.4 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/generate-status-page.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/generate-status-page.sh ~/awsc-new/awesome/orchestrator /tmp/test-status.html && test -f /tmp/test-status.html && echo GENERATED` → expect `GENERATED`
3. `grep -c "<html" /tmp/test-status.html` → expect `1`
4. `grep -c "orchestrator-sprint4" /tmp/test-status.html` → expect at least `1`
5. `grep -c "phase" /tmp/test-status.html` → expect at least `5` (one per phase)
6. `grep "<style>" /tmp/test-status.html` → expect match (inline CSS present)
7. `wc -c < /tmp/test-status.html | awk '{print ($1 > 1000) ? "SIZE_OK" : "TOO_SMALL"}'` → expect `SIZE_OK`
8. `rm -f /tmp/test-status.html && grep "4.4" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/04-status-web-page/result.md`
4. Commit with prefix: `[orchestrator-sprint4-04]`
5. Do NOT push
