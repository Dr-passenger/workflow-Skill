# Inspection Guide

Use this guide for daily reports and explicit code, environment, or model-run checks.

## Evidence order

Prefer evidence in this order:

1. Current command output or file content
2. A stored inspection snapshot from the same day
3. A task result or typed note
4. The user's direct statement
5. `未采集` or `未记录`

Never convert an inference into a measured fact. Include timestamps for state that can change.

## Code inspection

For every configured repository, capture:

- resolved path and whether it exists
- current branch or detached state
- latest commit ID, time, and subject
- counts of staged, modified, untracked, and conflicted files
- recent changes relevant to today's tasks
- failing or unrun tests, when test evidence is available

Do not discard or modify a dirty worktree during inspection. Do not expose secret file contents.

## Training environment inspection

Capture only tools that are actually detected:

- operating system and PowerShell version
- Python, Conda, Git, and NVIDIA tooling versions
- active or configured environment name when observable
- visible GPU inventory and utilization from `nvidia-smi`
- matching training processes with PID and start time
- dependency or configuration drift relevant to current work

A visible process is not proof of progress or health. Confirm progress through recent logs, checkpoints, metrics, or an explicit user statement.

## Model-run inspection

Configure `modelResultPaths` with exact files or narrow wildcard patterns. For each relevant run, seek:

- run name or ID
- model/config/dataset version
- start/end/state
- latest step or epoch
- primary metrics and comparison baseline
- checkpoint or artifact path
- failure, warning, or anomaly evidence
- next action

Avoid recursively scanning broad disks. Read only relevant result files. Quote short values, not entire logs. If different runs use different metric names, preserve the original names.

## Safety

- Keep the inspection read-only.
- Never run training, tests, package upgrades, environment activation, or cleanup merely to complete a report.
- Ask before executing a costly validation job.
- Redact tokens, passwords, internal URLs with credentials, and personal data.
