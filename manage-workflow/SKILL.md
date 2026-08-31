---
name: manage-workflow
description: Manage a local engineering and model-training workflow from natural-language requests. Use for daily task planning, inserting temporary or urgent work, updating task status, maintaining Markdown and ICS calendars, inspecting Git repositories and training environments, recording model-run evidence, producing end-of-day reports covering today's plan/code/environment/model results/next-day preparation, and producing weekly task and workflow reviews.
---

# Manage Workflow

Maintain one evidence-based local work ledger and derive schedules and reports from it. Never invent task completion, environment health, or model metrics.

## Resolve the workflow home

Use this order:

1. Use the path explicitly named by the user.
2. Use `WORKFLOW_HOME` when it is set.
3. Reuse the nearest existing `.workflow/config.json` found from the current directory upward.
4. For a project-scoped workflow, use `<project>/.workflow`.
5. If scope is genuinely ambiguous, ask once where the durable work ledger should live.

Store user data in the workflow home, never inside this skill directory. Run the bundled script with an absolute skill path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action doctor -WorkflowHome "<workflow-home>"
```

Use `powershell.exe` or `powershell` on Windows. On Linux or macOS, use `pwsh` when PowerShell 7 is installed; keep the remaining arguments unchanged.

On first use, run `-Action init`. Inspect the generated `config.json`, then add repository paths and exact model-result paths when known. Preserve existing configuration and records.

## Apply the operating rules

- Treat `tasks.json` and `notes.json` as canonical. Do not hand-edit derived calendar files.
- Use local dates as `YYYY-MM-DD` and times as `HH:mm`.
- Record every meaningful schedule or status change immediately.
- Use task statuses only from `todo`, `in-progress`, `blocked`, `done`, and `cancelled`.
- Use priorities `P0` through `P3`, where `P0` is urgent and blocking and `P3` is low priority.
- Mark unplanned inserted work with `-Temporary` so reports expose interruptions.
- Before moving or cancelling an existing item, explain the affected task. Do not silently erase commitments.
- Before adding a timed item, check the target date with `-Action list`. Let conflict detection stop overlaps. Use `-Force` only when the user explicitly accepts overlap or the schedule is intentionally concurrent.
- After task mutations, rely on the script's automatic calendar refresh.
- Keep model metrics tied to a run, checkpoint, log, or user statement. Mark absent evidence as `未采集` or `未记录`.
- Keep secrets, tokens, `.env` values, and full command lines containing credentials out of notes and reports.

## Map natural language to actions

### Initialize or verify

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action init -WorkflowHome "<workflow-home>"
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action doctor -WorkflowHome "<workflow-home>"
```

### Add planned or temporary work

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action add-task -WorkflowHome "<workflow-home>" -Title "训练基线模型" -Date "2026-09-01" -Start "10:00" -End "12:00" -Priority P1 -Category training -Project "project-a"

powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action add-task -WorkflowHome "<workflow-home>" -Title "临时排查显存溢出" -Date "2026-09-01" -Start "14:00" -End "15:00" -Priority P0 -Category incident -Project "project-a" -Temporary
```

If the user omits a time, create an all-day task. If the date is omitted but the language clearly says today or tomorrow, resolve it using the local date. Otherwise ask for the date rather than guessing.

### Update execution state

First list tasks to resolve the ID, then update only stated fields:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action list -WorkflowHome "<workflow-home>" -Date "2026-09-01"
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action update-task -WorkflowHome "<workflow-home>" -Id "T-..." -Status done -Result "best val_loss=0.184；checkpoint=epoch_12"
```

Use `-ClearTime` when intentionally converting a timed task to all-day. Use `-TemporaryValue true|false` to correct the temporary-work marker.

### Record evidence and decisions

Use notes for facts that are not task fields:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action add-note -WorkflowHome "<workflow-home>" -Date "2026-09-01" -Kind model-result -Project "project-a" -Text "run-042: val_loss=0.184, F1=0.912, checkpoint=epoch_12"
```

Allowed note kinds are `worklog`, `code`, `environment`, `model-result`, `risk`, `decision`, and `next-day`.

### Inspect code, training environment, and model artifacts

Read [references/inspection.md](references/inspection.md) before a requested inspection or report. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action inspect -WorkflowHome "<workflow-home>" -Date "2026-09-01"
```

The script captures a read-only baseline. Supplement it by reading the configured logs or metric files necessary for the user's report. Do not claim that a process is healthy merely because it exists.

### Maintain the schedule

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action calendar -WorkflowHome "<workflow-home>" -From "2026-09-01" -To "2026-09-07"
```

The command writes `calendar/schedule.md` and `calendar/schedule.ics`. Use the Markdown file for review and the ICS file for importing into calendar applications.

## Run the daily workflow

### Start of day

1. List today's tasks and overdue unfinished tasks.
2. Surface time conflicts, P0/P1 items, blocked items, and carry-over work.
3. Inspect configured repositories, training tools, running processes, and model-result files when the user asks for an environment check or a daily plan that requires current state.
4. Propose an ordered plan with realistic time blocks. Preserve fixed commitments and identify assumptions.
5. Save accepted changes as tasks and refresh the calendar.

### During the day

For a temporary insertion:

1. Capture title, date, duration or time window, priority, project, and intended outcome from context.
2. List that day's schedule and check overlap.
3. Add the item with `-Temporary` if it fits.
4. If it conflicts, prefer moving flexible lower-priority work, splitting it, or carrying it forward. Describe the change before applying it. Never mark displaced work done.
5. Record incident conclusions or model evidence as a task result or typed note.

### End of day

1. Reconcile today's tasks against explicit evidence.
2. Run `inspect` unless a current snapshot already exists and no relevant state changed.
3. Record any supplied model metrics or outcomes.
4. Generate the report:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action daily-report -WorkflowHome "<workflow-home>" -Date "2026-09-01"
```

5. Read the generated report and refine it using [references/reporting.md](references/reporting.md). Keep missing data visible; do not replace it with optimistic prose.

## Run the weekly workflow

Use any date in the target Monday-through-Sunday week:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>/scripts/workflow.ps1" -Action weekly-report -WorkflowHome "<workflow-home>" -Week "2026-09-03"
```

Then read the generated report and refine it using [references/reporting.md](references/reporting.md). Cover delivery, model-learning evidence, interruptions, bottlenecks, carry-over work, workflow adjustments, and next-week priorities. Convert accepted next-week actions into dated tasks rather than leaving them only in prose.

## Finish each request

State what changed, name the generated report or calendar path, flag conflicts or missing evidence, and mention the next decision only when one is needed. Keep the response concise; the durable detail belongs in the workflow home.
