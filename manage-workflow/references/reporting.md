# Reporting Guide

Use this guide after the script creates a daily or weekly Markdown draft.

## Daily report contract

Keep these sections, even when evidence is absent:

1. `当日任务安排与执行` — planned window, priority, status, result, and temporary-work marker
2. `代码与训练环境检视` — repository state, environment/tool state, running training processes, risks
3. `模型运行结果` — run identity, metrics, baseline comparison, artifact, conclusion; otherwise `未记录`
4. `问题、阻塞与决策` — blocker, impact, owner or next action
5. `次日任务预备` — dated tasks, dependencies, environment/data/checkpoint preparation

Separate facts from interpretation. Use exact metric names and values. For incomplete work, say what remains instead of using a vague percentage unless the percentage is evidenced.

## Weekly report contract

Cover:

- the Monday-to-Sunday date range
- planned, completed, blocked, cancelled, carried-over, and temporary task counts
- major deliverables by project
- model experiments and what was learned, including negative results
- interruption load and its impact on planned work
- repeated blockers or workflow friction
- one to three concrete workflow adjustments
- next week's P0/P1 outcomes and preparation

Treat a task as carried over when it was scheduled in the week on or before the report's as-of date, remains unfinished, and is not cancelled. Do not treat a later task in the same week as carry-over, and do not count a task created next week as a completed weekly deliverable.

## Writing rules

- Put outcomes before activity lists.
- Prefer tables for schedules and run-to-run metric comparisons.
- Keep raw logs out of the report; link or name the evidence file.
- Mark inference explicitly with `推断：`.
- Mark absent evidence with `未采集` or `未记录`.
- Preserve blockers and negative results; they are useful workflow evidence.
- Turn accepted next steps into ledger tasks with dates.
