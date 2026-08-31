[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'doctor', 'add-task', 'update-task', 'list', 'add-note', 'inspect', 'calendar', 'daily-report', 'weekly-report')]
    [string]$Action,

    [string]$WorkflowHome = $env:WORKFLOW_HOME,
    [string]$Id,
    [string]$Title,
    [string]$Date,
    [string]$Start,
    [string]$End,
    [ValidateSet('P0', 'P1', 'P2', 'P3')]
    [string]$Priority,
    [string]$Category,
    [ValidateSet('todo', 'in-progress', 'blocked', 'done', 'cancelled')]
    [string]$Status,
    [string]$Project,
    [string]$Notes,
    [string]$Result,
    [switch]$Temporary,
    [ValidateSet('true', 'false')]
    [string]$TemporaryValue,
    [switch]$ClearTime,
    [switch]$Force,
    [string]$Kind,
    [string]$Text,
    [string]$From,
    [string]$To,
    [string]$Week,
    [string]$Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProvidedParameters = @{}
foreach ($parameterName in $PSBoundParameters.Keys) {
    $script:ProvidedParameters[$parameterName] = $true
}

if ([string]::IsNullOrWhiteSpace($WorkflowHome)) {
    $WorkflowHome = Join-Path (Get-Location).Path '.workflow'
}
$script:WorkflowHome = [System.IO.Path]::GetFullPath($WorkflowHome)
$script:ConfigPath = Join-Path $script:WorkflowHome 'config.json'
$script:TasksPath = Join-Path $script:WorkflowHome 'tasks.json'
$script:NotesPath = Join-Path $script:WorkflowHome 'notes.json'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporaryPath = Join-Path $parent ('.tmp-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 12
        Write-TextFile -Path $temporaryPath -Content ($json + [Environment]::NewLine)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Read-JsonArray {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing data file: $Path. Run -Action init first."
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }
    $value = ConvertFrom-Json -InputObject $raw
    if ($null -eq $value) {
        return @()
    }
    return @($value)
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "Missing config: $script:ConfigPath. Run -Action init first."
    }
    return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8)
}

function Assert-Initialized {
    $missing = @()
    foreach ($path in @($script:ConfigPath, $script:TasksPath, $script:NotesPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            $missing += $path
        }
    }
    if ($missing.Count -gt 0) {
        throw ('Workflow home is not initialized. Missing: ' + ($missing -join ', ') + '. Run -Action init.')
    }
}

function Parse-DateValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Name = 'date'
    )
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if (-not $ok) {
        throw "$Name must use YYYY-MM-DD: $Value"
    }
    return $parsed.Date
}

function Parse-TimeValue {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Name = 'time'
    )
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Value,
        'HH:mm',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
    if (-not $ok) {
        throw "$Name must use HH:mm: $Value"
    }
    return $parsed
}

function Test-UnfinishedStatus {
    param([string]$Value)
    return $Value -in @('todo', 'in-progress', 'blocked')
}

function ConvertTo-MarkdownCell {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return '-'
    }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", '<br>')
}

function ConvertTo-IcsText {
    param($Value)
    if ($null -eq $Value) { return '' }
    $textValue = [string]$Value
    $textValue = $textValue.Replace('\', '\\')
    $textValue = $textValue.Replace(';', '\;').Replace(',', '\,')
    return $textValue.Replace("`r`n", '\n').Replace("`n", '\n').Replace("`r", '\n')
}

function Resolve-ConfiguredPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $containsWildcard = $expanded.Contains('*') -or $expanded.Contains('?')
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }
    $combined = Join-Path $script:WorkflowHome $expanded
    if ($containsWildcard) {
        return $combined
    }
    return [System.IO.Path]::GetFullPath($combined)
}

function Get-ScheduleConflicts {
    param(
        [Parameter(Mandatory = $true)]$Tasks,
        [Parameter(Mandatory = $true)][string]$TargetDate,
        [Parameter(Mandatory = $true)][string]$TargetStart,
        [Parameter(Mandatory = $true)][string]$TargetEnd,
        [string]$ExcludeId
    )
    $startValue = Parse-TimeValue -Value $TargetStart -Name 'Start'
    $endValue = Parse-TimeValue -Value $TargetEnd -Name 'End'
    if ($endValue -le $startValue) {
        throw 'End must be later than Start on the same date.'
    }
    $conflicts = @()
    foreach ($task in @($Tasks)) {
        if ($task.id -eq $ExcludeId -or $task.date -ne $TargetDate -or $task.status -eq 'cancelled') { continue }
        if ([string]::IsNullOrWhiteSpace([string]$task.start) -or [string]::IsNullOrWhiteSpace([string]$task.end)) { continue }
        $existingStart = Parse-TimeValue -Value ([string]$task.start)
        $existingEnd = Parse-TimeValue -Value ([string]$task.end)
        if ($startValue -lt $existingEnd -and $endValue -gt $existingStart) {
            $conflicts += $task
        }
    }
    return $conflicts
}

function Get-TaskSortKey {
    param($Task)
    $time = if ([string]::IsNullOrWhiteSpace([string]$Task.start)) { '99:99' } else { [string]$Task.start }
    return ('{0}|{1}|{2}|{3}' -f $Task.date, $time, $Task.priority, $Task.createdAt)
}

function Write-CalendarFiles {
    param(
        [Parameter(Mandatory = $true)]$Tasks,
        [datetime]$RangeFrom,
        [datetime]$RangeTo
    )
    $calendarDir = Join-Path $script:WorkflowHome 'calendar'
    New-Item -ItemType Directory -Path $calendarDir -Force | Out-Null

    $selected = @($Tasks | Where-Object {
        if ($_.status -eq 'cancelled') { return $false }
        $taskDate = Parse-DateValue -Value ([string]$_.date)
        if ($RangeFrom -and $taskDate -lt $RangeFrom) { return $false }
        if ($RangeTo -and $taskDate -gt $RangeTo) { return $false }
        return $true
    } | Sort-Object @{ Expression = { Get-TaskSortKey -Task $_ } })

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('# 工作日程')
    $md.Add('')
    $md.Add('> 由 manage-workflow 自动生成；请通过任务账本更新，不要直接编辑。')
    $md.Add('')
    $md.Add('| 日期 | 时间 | 优先级 | 任务 | 项目 | 状态 | 临时 | ID |')
    $md.Add('|---|---|---|---|---|---|---|---|')
    foreach ($task in $selected) {
        $timeText = if ($task.start) { "$($task.start)-$($task.end)" } else { '全天' }
        $temporaryText = if ([bool]$task.temporary) { '是' } else { '否' }
        $md.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f
            (ConvertTo-MarkdownCell $task.date),
            (ConvertTo-MarkdownCell $timeText),
            (ConvertTo-MarkdownCell $task.priority),
            (ConvertTo-MarkdownCell $task.title),
            (ConvertTo-MarkdownCell $task.project),
            (ConvertTo-MarkdownCell $task.status),
            $temporaryText,
            (ConvertTo-MarkdownCell $task.id)))
    }
    if ($selected.Count -eq 0) {
        $md.Add('| - | - | - | 当前范围无任务 | - | - | - | - |')
    }
    $mdPath = Join-Path $calendarDir 'schedule.md'
    Write-TextFile -Path $mdPath -Content (($md -join [Environment]::NewLine) + [Environment]::NewLine)

    $ics = New-Object System.Collections.Generic.List[string]
    $ics.Add('BEGIN:VCALENDAR')
    $ics.Add('VERSION:2.0')
    $ics.Add('PRODID:-//manage-workflow//Local Workflow//ZH-CN')
    $ics.Add('CALSCALE:GREGORIAN')
    foreach ($task in $selected) {
        $taskDate = Parse-DateValue -Value ([string]$task.date)
        $ics.Add('BEGIN:VEVENT')
        $ics.Add('UID:' + (ConvertTo-IcsText "$($task.id)@manage-workflow.local"))
        $ics.Add('DTSTAMP:' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
        if ($task.start) {
            $startDateTime = [datetime]::ParseExact(
                "$($task.date) $($task.start)",
                'yyyy-MM-dd HH:mm',
                [Globalization.CultureInfo]::InvariantCulture
            )
            $endDateTime = [datetime]::ParseExact(
                "$($task.date) $($task.end)",
                'yyyy-MM-dd HH:mm',
                [Globalization.CultureInfo]::InvariantCulture
            )
            $ics.Add('DTSTART:' + $startDateTime.ToString('yyyyMMddTHHmmss'))
            $ics.Add('DTEND:' + $endDateTime.ToString('yyyyMMddTHHmmss'))
        }
        else {
            $ics.Add('DTSTART;VALUE=DATE:' + $taskDate.ToString('yyyyMMdd'))
            $ics.Add('DTEND;VALUE=DATE:' + $taskDate.AddDays(1).ToString('yyyyMMdd'))
        }
        $ics.Add('SUMMARY:' + (ConvertTo-IcsText $task.title))
        $descriptionParts = @(
            "priority=$($task.priority)",
            "status=$($task.status)",
            "project=$($task.project)",
            "temporary=$($task.temporary)",
            "notes=$($task.notes)",
            "result=$($task.result)"
        )
        $ics.Add('DESCRIPTION:' + (ConvertTo-IcsText ($descriptionParts -join "`n")))
        $ics.Add('CATEGORIES:' + (ConvertTo-IcsText $task.category))
        $ics.Add('END:VEVENT')
    }
    $ics.Add('END:VCALENDAR')
    $icsPath = Join-Path $calendarDir 'schedule.ics'
    Write-TextFile -Path $icsPath -Content (($ics -join "`r`n") + "`r`n")

    return [pscustomobject]@{ markdown = $mdPath; ics = $icsPath; count = $selected.Count }
}

function Sync-AllCalendars {
    $allTasks = @(Read-JsonArray -Path $script:TasksPath)
    return Write-CalendarFiles -Tasks $allTasks
}

function Initialize-Workflow {
    New-Item -ItemType Directory -Path $script:WorkflowHome -Force | Out-Null
    foreach ($directory in @('calendar', 'snapshots', 'reports/daily', 'reports/weekly')) {
        New-Item -ItemType Directory -Path (Join-Path $script:WorkflowHome $directory) -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        $config = [ordered]@{
            version = 1
            timezone = 'Asia/Shanghai'
            workingHours = [ordered]@{ start = '09:00'; end = '18:00' }
            repositories = @()
            training = [ordered]@{
                processNames = @('python', 'python3', 'torchrun', 'accelerate', 'deepspeed')
                modelResultPaths = @()
            }
        }
        Write-JsonFile -Path $script:ConfigPath -Value $config
    }
    if (-not (Test-Path -LiteralPath $script:TasksPath)) {
        Write-JsonFile -Path $script:TasksPath -Value @()
    }
    if (-not (Test-Path -LiteralPath $script:NotesPath)) {
        Write-JsonFile -Path $script:NotesPath -Value @()
    }
    $calendar = Sync-AllCalendars
    Write-Output "Initialized workflow home: $script:WorkflowHome"
    Write-Output "Config: $script:ConfigPath"
    Write-Output "Calendar: $($calendar.markdown)"
}

function Add-Task {
    Assert-Initialized
    if ([string]::IsNullOrWhiteSpace($Title)) { throw 'Title is required for add-task.' }
    if ([string]::IsNullOrWhiteSpace($Date)) { throw 'Date is required for add-task and must use YYYY-MM-DD.' }
    [void](Parse-DateValue -Value $Date)
    if ([string]::IsNullOrWhiteSpace($Priority)) { $script:Priority = 'P2' }
    if ([string]::IsNullOrWhiteSpace($Category)) { $script:Category = 'general' }
    if ([string]::IsNullOrWhiteSpace($Status)) { $script:Status = 'todo' }
    if (($Start -and -not $End) -or ($End -and -not $Start)) {
        throw 'Start and End must be provided together.'
    }
    if ($Start) {
        [void](Parse-TimeValue -Value $Start -Name 'Start')
        [void](Parse-TimeValue -Value $End -Name 'End')
    }

    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    if ($Start) {
        $conflicts = @(Get-ScheduleConflicts -Tasks $tasks -TargetDate $Date -TargetStart $Start -TargetEnd $End)
        if ($conflicts.Count -gt 0 -and -not $Force) {
            $details = @($conflicts | ForEach-Object { "$($_.id) [$($_.start)-$($_.end)] $($_.title)" }) -join '; '
            throw "Schedule conflict detected: $details. Move a task or rerun with -Force for intentional overlap."
        }
    }

    $now = (Get-Date).ToString('o')
    $newId = 'T-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 4))
    $task = [ordered]@{
        id = $newId
        title = $Title.Trim()
        date = $Date
        start = if ($Start) { $Start } else { '' }
        end = if ($End) { $End } else { '' }
        priority = $Priority
        category = $Category
        status = $Status
        project = if ($Project) { $Project } else { '' }
        temporary = [bool]$Temporary
        notes = if ($Notes) { $Notes } else { '' }
        result = if ($Result) { $Result } else { '' }
        createdAt = $now
        updatedAt = $now
    }
    $tasks += [pscustomobject]$task
    Write-JsonFile -Path $script:TasksPath -Value @($tasks)
    $calendar = Sync-AllCalendars
    Write-Output "Added task ${newId}: $Title"
    Write-Output "Calendar updated: $($calendar.markdown)"
}

function Update-Task {
    Assert-Initialized
    if ([string]::IsNullOrWhiteSpace($Id)) { throw 'Id is required for update-task.' }
    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    $matches = @($tasks | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Expected one task with ID $Id; found $($matches.Count)." }
    $task = $matches[0]

    $targetDate = if ($script:ProvidedParameters.ContainsKey('Date')) { $Date } else { [string]$task.date }
    $targetStart = if ($script:ProvidedParameters.ContainsKey('Start')) { $Start } else { [string]$task.start }
    $targetEnd = if ($script:ProvidedParameters.ContainsKey('End')) { $End } else { [string]$task.end }
    if ($ClearTime) { $targetStart = ''; $targetEnd = '' }
    [void](Parse-DateValue -Value $targetDate)
    if (($targetStart -and -not $targetEnd) -or ($targetEnd -and -not $targetStart)) {
        throw 'Start and End must be provided together.'
    }
    if ($targetStart) {
        $conflicts = @(Get-ScheduleConflicts -Tasks $tasks -TargetDate $targetDate -TargetStart $targetStart -TargetEnd $targetEnd -ExcludeId $Id)
        if ($conflicts.Count -gt 0 -and -not $Force) {
            $details = @($conflicts | ForEach-Object { "$($_.id) [$($_.start)-$($_.end)] $($_.title)" }) -join '; '
            throw "Schedule conflict detected: $details. Move a task or rerun with -Force for intentional overlap."
        }
    }

    if ($script:ProvidedParameters.ContainsKey('Title')) {
        if ([string]::IsNullOrWhiteSpace($Title)) { throw 'Title cannot be empty.' }
        $task.title = $Title.Trim()
    }
    if ($script:ProvidedParameters.ContainsKey('Date')) { $task.date = $Date }
    $task.start = $targetStart
    $task.end = $targetEnd
    if ($script:ProvidedParameters.ContainsKey('Priority')) { $task.priority = $Priority }
    if ($script:ProvidedParameters.ContainsKey('Category')) { $task.category = $Category }
    if ($script:ProvidedParameters.ContainsKey('Status')) { $task.status = $Status }
    if ($script:ProvidedParameters.ContainsKey('Project')) { $task.project = $Project }
    if ($script:ProvidedParameters.ContainsKey('Notes')) { $task.notes = $Notes }
    if ($script:ProvidedParameters.ContainsKey('Result')) { $task.result = $Result }
    if ($script:ProvidedParameters.ContainsKey('TemporaryValue')) { $task.temporary = ($TemporaryValue -eq 'true') }
    $task.updatedAt = (Get-Date).ToString('o')

    Write-JsonFile -Path $script:TasksPath -Value @($tasks)
    $calendar = Sync-AllCalendars
    Write-Output "Updated task $Id."
    Write-Output "Calendar updated: $($calendar.markdown)"
}

function List-Tasks {
    Assert-Initialized
    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    if ($Date) {
        [void](Parse-DateValue -Value $Date)
        $tasks = @($tasks | Where-Object { $_.date -eq $Date })
    }
    if ($From) {
        $fromDate = Parse-DateValue -Value $From -Name 'From'
        $tasks = @($tasks | Where-Object { (Parse-DateValue -Value ([string]$_.date)) -ge $fromDate })
    }
    if ($To) {
        $toDate = Parse-DateValue -Value $To -Name 'To'
        $tasks = @($tasks | Where-Object { (Parse-DateValue -Value ([string]$_.date)) -le $toDate })
    }
    if ($Status) {
        $tasks = @($tasks | Where-Object { $_.status -eq $Status })
    }
    $tasks = @($tasks | Sort-Object @{ Expression = { Get-TaskSortKey -Task $_ } })
    if ($tasks.Count -eq 0) {
        Write-Output 'No matching tasks.'
        return
    }
    $tasks | Select-Object id, date, start, end, priority, status, temporary, project, category, title | Format-Table -AutoSize
}

function Add-WorkflowNote {
    Assert-Initialized
    $allowedKinds = @('worklog', 'code', 'environment', 'model-result', 'risk', 'decision', 'next-day')
    if ([string]::IsNullOrWhiteSpace($Kind) -or $Kind -notin $allowedKinds) {
        throw ('Kind must be one of: ' + ($allowedKinds -join ', '))
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Text is required for add-note.' }
    if ([string]::IsNullOrWhiteSpace($Date)) { $script:Date = (Get-Date).ToString('yyyy-MM-dd') }
    [void](Parse-DateValue -Value $Date)
    $noteList = @(Read-JsonArray -Path $script:NotesPath)
    $noteId = 'N-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 4))
    $note = [ordered]@{
        id = $noteId
        date = $Date
        kind = $Kind
        project = if ($Project) { $Project } else { '' }
        text = $Text.Trim()
        createdAt = (Get-Date).ToString('o')
    }
    $noteList += [pscustomobject]$note
    Write-JsonFile -Path $script:NotesPath -Value @($noteList)
    Write-Output "Added note $noteId ($Kind)."
}

function Invoke-ExternalCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @()
    )
    try {
        $captured = & $Executable @Arguments 2>&1 | Out-String
        return [pscustomobject]@{
            ok = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
            output = $captured.Trim()
            exitCode = $LASTEXITCODE
        }
    }
    catch {
        return [pscustomobject]@{ ok = $false; output = $_.Exception.Message; exitCode = -1 }
    }
}

function Get-RepositoryInspection {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        $GitCommand
    )
    $resolved = Resolve-ConfiguredPath -Path $RepositoryPath
    $record = [ordered]@{
        configuredPath = $RepositoryPath
        path = $resolved
        exists = (Test-Path -LiteralPath $resolved -PathType Container)
        isGitRepository = $false
        branch = ''
        head = ''
        lastCommitAt = ''
        lastCommitSubject = ''
        staged = 0
        modified = 0
        untracked = 0
        conflicted = 0
        error = ''
    }
    if (-not $record.exists) { return [pscustomobject]$record }
    if ($null -eq $GitCommand) {
        $record.error = 'git not found'
        return [pscustomobject]$record
    }
    $inside = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'rev-parse', '--is-inside-work-tree')
    if (-not $inside.ok -or $inside.output -ne 'true') {
        $record.error = 'not a Git worktree'
        return [pscustomobject]$record
    }
    $record.isGitRepository = $true
    $branch = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'branch', '--show-current')
    $head = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'rev-parse', '--short', 'HEAD')
    $commitAt = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'log', '-1', '--format=%cI')
    $subject = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'log', '-1', '--format=%s')
    $statusOutput = Invoke-ExternalCapture -Executable $GitCommand.Source -Arguments @('-C', $resolved, 'status', '--porcelain=v1')
    if ($branch.ok) { $record.branch = $branch.output }
    if ($head.ok) { $record.head = $head.output }
    if ($commitAt.ok) { $record.lastCommitAt = $commitAt.output }
    if ($subject.ok) { $record.lastCommitSubject = $subject.output }
    if ($statusOutput.ok -and $statusOutput.output) {
        foreach ($line in @($statusOutput.output -split "`r?`n")) {
            if ($line.Length -lt 2) { continue }
            $xy = $line.Substring(0, 2)
            if ($xy -eq '??') { $record.untracked++; continue }
            if ($xy -match 'U|AA|DD') { $record.conflicted++ }
            if ($xy[0] -ne ' ') { $record.staged++ }
            if ($xy[1] -ne ' ') { $record.modified++ }
        }
    }
    return [pscustomobject]$record
}

function Inspect-Workflow {
    Assert-Initialized
    if ([string]::IsNullOrWhiteSpace($Date)) { $script:Date = (Get-Date).ToString('yyyy-MM-dd') }
    [void](Parse-DateValue -Value $Date)
    $config = Read-Config
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    $repositories = @()
    foreach ($repo in @($config.repositories)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$repo)) {
            $repositories += Get-RepositoryInspection -RepositoryPath ([string]$repo) -GitCommand $gitCommand
        }
    }

    $toolSpecifications = @(
        [pscustomobject]@{ name = 'git'; arguments = @('--version') },
        [pscustomobject]@{ name = 'python'; arguments = @('--version') },
        [pscustomobject]@{ name = 'python3'; arguments = @('--version') },
        [pscustomobject]@{ name = 'conda'; arguments = @('--version') }
    )
    $tools = @()
    foreach ($spec in $toolSpecifications) {
        $command = Get-Command $spec.name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $version = Invoke-ExternalCapture -Executable $command.Source -Arguments $spec.arguments
            $tools += [pscustomobject]@{
                name = $spec.name
                path = $command.Source
                version = $version.output
                ok = $version.ok
            }
        }
    }

    $gpu = @()
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($null -ne $nvidia) {
        $gpuQuery = Invoke-ExternalCapture -Executable $nvidia.Source -Arguments @(
            '--query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu',
            '--format=csv,noheader,nounits'
        )
        if ($gpuQuery.ok -and $gpuQuery.output) {
            foreach ($line in @($gpuQuery.output -split "`r?`n")) {
                $parts = @($line -split ',' | ForEach-Object { $_.Trim() })
                if ($parts.Count -ge 6) {
                    $gpu += [pscustomobject]@{
                        index = $parts[0]
                        name = $parts[1]
                        driver = $parts[2]
                        memoryTotalMiB = $parts[3]
                        memoryUsedMiB = $parts[4]
                        utilizationPercent = $parts[5]
                    }
                }
            }
        }
    }

    $configuredNames = @($config.training.processNames | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $processes = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.ProcessName.ToLowerInvariant() -in $configuredNames) {
            $startTime = ''
            try { $startTime = $process.StartTime.ToString('o') } catch { $startTime = 'unavailable' }
            $processes += [pscustomobject]@{
                name = $process.ProcessName
                id = $process.Id
                cpuSeconds = [math]::Round($process.CPU, 2)
                startTime = $startTime
            }
        }
    }

    $artifacts = @()
    foreach ($configuredPath in @($config.training.modelResultPaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$configuredPath)) { continue }
        $resolvedPattern = Resolve-ConfiguredPath -Path ([string]$configuredPath)
        $items = @()
        try {
            if (Test-Path -LiteralPath $resolvedPattern -PathType Leaf) {
                $items = @(Get-Item -LiteralPath $resolvedPattern)
            }
            elseif (Test-Path -LiteralPath $resolvedPattern -PathType Container) {
                $items = @(Get-ChildItem -LiteralPath $resolvedPattern -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 20)
            }
            else {
                $items = @(Get-ChildItem -Path $resolvedPattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 20)
            }
        }
        catch {
            $items = @()
        }
        if ($items.Count -eq 0) {
            $artifacts += [pscustomobject]@{
                configuredPath = [string]$configuredPath
                path = $resolvedPattern
                exists = $false
                length = 0
                lastWriteTime = ''
            }
        }
        else {
            foreach ($item in $items) {
                $artifacts += [pscustomobject]@{
                    configuredPath = [string]$configuredPath
                    path = $item.FullName
                    exists = $true
                    length = $item.Length
                    lastWriteTime = $item.LastWriteTime.ToString('o')
                }
            }
        }
    }

    $snapshot = [ordered]@{
        schemaVersion = 1
        date = $Date
        capturedAt = (Get-Date).ToString('o')
        machine = [ordered]@{
            name = [Environment]::MachineName
            os = [Environment]::OSVersion.VersionString
            powershell = $PSVersionTable.PSVersion.ToString()
        }
        repositories = @($repositories)
        tools = @($tools)
        gpu = @($gpu)
        trainingProcesses = @($processes)
        modelArtifacts = @($artifacts)
    }
    $snapshotDir = Join-Path $script:WorkflowHome 'snapshots'
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    $snapshotPath = Join-Path $snapshotDir ("$Date-" + (Get-Date).ToString('HHmmss') + '.json')
    Write-JsonFile -Path $snapshotPath -Value $snapshot
    Write-JsonFile -Path (Join-Path $snapshotDir 'latest.json') -Value $snapshot
    Write-Output "Inspection snapshot: $snapshotPath"
    Write-Output "Repositories: $($repositories.Count); tools: $($tools.Count); GPUs: $($gpu.Count); matching processes: $($processes.Count); model artifacts: $($artifacts.Count)"
}

function Get-LatestSnapshotForDate {
    param([Parameter(Mandatory = $true)][string]$TargetDate)
    $snapshotDir = Join-Path $script:WorkflowHome 'snapshots'
    if (-not (Test-Path -LiteralPath $snapshotDir)) { return $null }
    $file = Get-ChildItem -LiteralPath $snapshotDir -Filter "$TargetDate-*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $file) { return $null }
    return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
}

function Add-TaskTable {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)]$Tasks,
        [string]$EmptyText = '无记录'
    )
    $Lines.Add('| 时间 | 优先级 | 任务 | 项目 | 状态 | 临时 | 结果 |')
    $Lines.Add('|---|---|---|---|---|---|---|')
    if (@($Tasks).Count -eq 0) {
        $Lines.Add("| - | - | $EmptyText | - | - | - | - |")
        return
    }
    foreach ($task in @($Tasks | Sort-Object @{ Expression = { Get-TaskSortKey -Task $_ } })) {
        $timeText = if ($task.start) { "$($task.start)-$($task.end)" } else { '全天' }
        $temporaryText = if ([bool]$task.temporary) { '是' } else { '否' }
        $Lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f
            (ConvertTo-MarkdownCell $timeText),
            (ConvertTo-MarkdownCell $task.priority),
            (ConvertTo-MarkdownCell $task.title),
            (ConvertTo-MarkdownCell $task.project),
            (ConvertTo-MarkdownCell $task.status),
            $temporaryText,
            (ConvertTo-MarkdownCell $task.result)))
    }
}

function Add-NotesSection {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)]$NotesToRender,
        [Parameter(Mandatory = $true)][string[]]$Kinds
    )
    $selected = @($NotesToRender | Where-Object { $_.kind -in $Kinds })
    if ($selected.Count -eq 0) {
        $Lines.Add('- 未记录')
        return
    }
    foreach ($note in $selected) {
        $projectPrefix = if ($note.project) { "[$($note.project)] " } else { '' }
        $Lines.Add("- **$($note.kind)**：$projectPrefix$($note.text)")
    }
}

function New-DailyReport {
    Assert-Initialized
    if ([string]::IsNullOrWhiteSpace($Date)) { $script:Date = (Get-Date).ToString('yyyy-MM-dd') }
    $targetDate = Parse-DateValue -Value $Date
    $nextDateString = $targetDate.AddDays(1).ToString('yyyy-MM-dd')
    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    $noteList = @(Read-JsonArray -Path $script:NotesPath)
    $todayTasks = @($tasks | Where-Object { $_.date -eq $Date })
    $overdue = @($tasks | Where-Object {
        (Parse-DateValue -Value ([string]$_.date)) -lt $targetDate -and (Test-UnfinishedStatus -Value ([string]$_.status))
    })
    $nextTasks = @($tasks | Where-Object { $_.date -eq $nextDateString -and $_.status -ne 'cancelled' })
    $todayNotes = @($noteList | Where-Object { $_.date -eq $Date })
    $snapshot = Get-LatestSnapshotForDate -TargetDate $Date

    $doneCount = @($todayTasks | Where-Object status -eq 'done').Count
    $blockedCount = @($todayTasks | Where-Object status -eq 'blocked').Count
    $temporaryCount = @($todayTasks | Where-Object { [bool]$_.temporary }).Count
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 每日工作汇报：$Date")
    $lines.Add('')
    $lines.Add("- 任务总数：$($todayTasks.Count)；完成：$doneCount；阻塞：$blockedCount；临时插入：$temporaryCount")
    $lines.Add("- 逾期未完成：$($overdue.Count)")
    $lines.Add('- 生成时间：' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $lines.Add('')
    $lines.Add('## 当日任务安排与执行')
    $lines.Add('')
    Add-TaskTable -Lines $lines -Tasks $todayTasks -EmptyText '当日无任务记录'
    if ($overdue.Count -gt 0) {
        $lines.Add('')
        $lines.Add('### 逾期未完成')
        $lines.Add('')
        Add-TaskTable -Lines $lines -Tasks $overdue
    }
    $lines.Add('')
    $lines.Add('## 代码与训练环境检视')
    $lines.Add('')
    if ($null -eq $snapshot) {
        $lines.Add('- 未采集：当天没有 inspection snapshot。')
    }
    else {
        $lines.Add("- 快照时间：$($snapshot.capturedAt)；机器：$($snapshot.machine.name)；系统：$($snapshot.machine.os)")
        if (@($snapshot.repositories).Count -eq 0) {
            $lines.Add('- 代码仓库：未配置或未采集。')
        }
        else {
            $lines.Add('')
            $lines.Add('| 仓库 | 分支 | HEAD | staged | modified | untracked | conflicted | 状态 |')
            $lines.Add('|---|---|---|---:|---:|---:|---:|---|')
            foreach ($repo in @($snapshot.repositories)) {
                $repoState = if ($repo.error) { $repo.error } else { '已采集' }
                $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f
                    (ConvertTo-MarkdownCell $repo.path),
                    (ConvertTo-MarkdownCell $repo.branch),
                    (ConvertTo-MarkdownCell $repo.head),
                    $repo.staged,
                    $repo.modified,
                    $repo.untracked,
                    $repo.conflicted,
                    (ConvertTo-MarkdownCell $repoState)))
            }
        }
        $toolText = @($snapshot.tools | ForEach-Object { "$($_.name): $($_.version)" }) -join '；'
        if ($toolText) { $lines.Add("- 工具：$toolText") } else { $lines.Add('- 工具：未检测到配置范围内的工具。') }
        if (@($snapshot.gpu).Count -gt 0) {
            foreach ($device in @($snapshot.gpu)) {
                $lines.Add("- GPU $($device.index) $($device.name)：显存 $($device.memoryUsedMiB)/$($device.memoryTotalMiB) MiB，利用率 $($device.utilizationPercent)%")
            }
        }
        else { $lines.Add('- GPU：未检测到 NVIDIA GPU 数据。') }
        if (@($snapshot.trainingProcesses).Count -gt 0) {
            foreach ($process in @($snapshot.trainingProcesses)) {
                $lines.Add("- 训练相关进程：$($process.name) PID=$($process.id)，启动=$($process.startTime)（仅表示进程存在，不代表运行健康）")
            }
        }
        else { $lines.Add('- 训练相关进程：未检测到。') }
    }
    $environmentNotes = @($todayNotes | Where-Object { $_.kind -in @('code', 'environment') })
    if ($environmentNotes.Count -gt 0) {
        $lines.Add('')
        Add-NotesSection -Lines $lines -NotesToRender $environmentNotes -Kinds @('code', 'environment')
    }

    $lines.Add('')
    $lines.Add('## 模型运行结果')
    $lines.Add('')
    Add-NotesSection -Lines $lines -NotesToRender $todayNotes -Kinds @('model-result')
    if ($null -ne $snapshot -and @($snapshot.modelArtifacts).Count -gt 0) {
        $lines.Add('')
        $lines.Add('### 已配置结果文件/制品')
        $lines.Add('')
        foreach ($artifact in @($snapshot.modelArtifacts)) {
            if ([bool]$artifact.exists) {
                $lines.Add("- $($artifact.path)（更新：$($artifact.lastWriteTime)，大小：$($artifact.length) bytes）")
            }
            else {
                $lines.Add("- 未找到：$($artifact.path)")
            }
        }
    }

    $lines.Add('')
    $lines.Add('## 问题、阻塞与决策')
    $lines.Add('')
    $blockers = @($todayTasks | Where-Object status -eq 'blocked')
    foreach ($task in $blockers) {
        $detail = if ($task.notes) { $task.notes } else { '阻塞原因未记录' }
        $lines.Add("- **$($task.title)**：$detail")
    }
    Add-NotesSection -Lines $lines -NotesToRender $todayNotes -Kinds @('risk', 'decision')

    $lines.Add('')
    $lines.Add("## 次日任务预备（$nextDateString）")
    $lines.Add('')
    Add-TaskTable -Lines $lines -Tasks $nextTasks -EmptyText '次日任务未安排'
    $nextDayNotes = @($noteList | Where-Object { $_.date -eq $Date -and $_.kind -eq 'next-day' })
    if ($nextDayNotes.Count -gt 0) {
        $lines.Add('')
        Add-NotesSection -Lines $lines -NotesToRender $nextDayNotes -Kinds @('next-day')
    }

    $reportPath = if ($Output) { [System.IO.Path]::GetFullPath($Output) } else {
        Join-Path (Join-Path $script:WorkflowHome 'reports/daily') "$Date.md"
    }
    Write-TextFile -Path $reportPath -Content (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
    Write-Output "Daily report: $reportPath"
}

function Get-WeekStart {
    param([datetime]$DateValue)
    $offset = (([int]$DateValue.DayOfWeek + 6) % 7)
    return $DateValue.Date.AddDays(-$offset)
}

function New-WeeklyReport {
    Assert-Initialized
    if ([string]::IsNullOrWhiteSpace($Week)) { $script:Week = (Get-Date).ToString('yyyy-MM-dd') }
    $weekDate = Parse-DateValue -Value $Week -Name 'Week'
    $weekStart = Get-WeekStart -DateValue $weekDate
    $weekEnd = $weekStart.AddDays(6)
    $nextWeekStart = $weekStart.AddDays(7)
    $nextWeekEnd = $weekStart.AddDays(13)
    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    $noteList = @(Read-JsonArray -Path $script:NotesPath)
    $weekTasks = @($tasks | Where-Object {
        $taskDate = Parse-DateValue -Value ([string]$_.date)
        $taskDate -ge $weekStart -and $taskDate -le $weekEnd
    })
    $weekNotes = @($noteList | Where-Object {
        $noteDate = Parse-DateValue -Value ([string]$_.date)
        $noteDate -ge $weekStart -and $noteDate -le $weekEnd
    })
    $nextWeekTasks = @($tasks | Where-Object {
        $taskDate = Parse-DateValue -Value ([string]$_.date)
        $taskDate -ge $nextWeekStart -and $taskDate -le $nextWeekEnd -and $_.status -ne 'cancelled'
    })
    $done = @($weekTasks | Where-Object status -eq 'done')
    $blocked = @($weekTasks | Where-Object status -eq 'blocked')
    $cancelled = @($weekTasks | Where-Object status -eq 'cancelled')
    $today = (Get-Date).Date
    $carryOverCutoff = if ($today -gt $weekEnd) {
        $weekEnd
    }
    elseif ($today -ge $weekStart) {
        $today
    }
    else {
        $weekStart.AddDays(-1)
    }
    $carryOver = @($weekTasks | Where-Object {
        (Parse-DateValue -Value ([string]$_.date)) -le $carryOverCutoff -and
        (Test-UnfinishedStatus -Value ([string]$_.status))
    })
    $temporaryTasks = @($weekTasks | Where-Object { [bool]$_.temporary })

    $calendar = [Globalization.CultureInfo]::InvariantCulture.Calendar
    $weekNumber = $calendar.GetWeekOfYear($weekStart, [Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
    $weekId = '{0}-W{1:D2}' -f $weekStart.Year, $weekNumber
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# 每周任务与工作流梳理：$weekId")
    $lines.Add('')
    $lines.Add("- 周期：$($weekStart.ToString('yyyy-MM-dd')) 至 $($weekEnd.ToString('yyyy-MM-dd'))")
    $lines.Add("- 任务：计划 $($weekTasks.Count)；完成 $($done.Count)；阻塞 $($blocked.Count)；取消 $($cancelled.Count)；结转 $($carryOver.Count)；临时插入 $($temporaryTasks.Count)")
    $lines.Add('- 生成时间：' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $lines.Add('')
    $lines.Add('## 本周交付与任务状态')
    $lines.Add('')
    Add-TaskTable -Lines $lines -Tasks $weekTasks -EmptyText '本周无任务记录'

    $lines.Add('')
    $lines.Add('## 模型实验与关键学习')
    $lines.Add('')
    Add-NotesSection -Lines $lines -NotesToRender $weekNotes -Kinds @('model-result')

    $lines.Add('')
    $lines.Add('## 临时事项与计划影响')
    $lines.Add('')
    Add-TaskTable -Lines $lines -Tasks $temporaryTasks -EmptyText '本周无临时插入任务'

    $lines.Add('')
    $lines.Add('## 阻塞、风险与决策')
    $lines.Add('')
    if ($blocked.Count -gt 0) {
        foreach ($task in $blocked) {
            $detail = if ($task.notes) { $task.notes } else { '阻塞原因未记录' }
            $lines.Add("- **$($task.title)**：$detail")
        }
    }
    Add-NotesSection -Lines $lines -NotesToRender $weekNotes -Kinds @('risk', 'decision')

    $lines.Add('')
    $lines.Add('## 工作流复盘与调整')
    $lines.Add('')
    if ($temporaryTasks.Count -ge 3) {
        $lines.Add("- 临时事项共 $($temporaryTasks.Count) 项；建议下周预留机动时段并复核临时事项来源。")
    }
    else {
        $lines.Add("- 临时事项共 $($temporaryTasks.Count) 项；继续观察其对主计划的影响。")
    }
    if ($blocked.Count -gt 0) {
        $lines.Add("- 阻塞任务共 $($blocked.Count) 项；为高优先级任务补充前置条件、责任人和最晚决策时间。")
    }
    if ($carryOver.Count -gt 0) {
        $lines.Add("- 结转任务共 $($carryOver.Count) 项；逐项决定继续、拆分、改期或取消，避免无期限滚动。")
    }
    if ($weekTasks.Count -eq 0) {
        $lines.Add('- 本周任务数据为空，无法据此评价工作流。')
    }

    $lines.Add('')
    $lines.Add("## 下周任务与预备（$($nextWeekStart.ToString('yyyy-MM-dd')) 至 $($nextWeekEnd.ToString('yyyy-MM-dd'))）")
    $lines.Add('')
    Add-TaskTable -Lines $lines -Tasks $nextWeekTasks -EmptyText '下周任务未安排'

    $reportPath = if ($Output) { [System.IO.Path]::GetFullPath($Output) } else {
        Join-Path (Join-Path $script:WorkflowHome 'reports/weekly') "$weekId.md"
    }
    Write-TextFile -Path $reportPath -Content (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
    Write-Output "Weekly report: $reportPath"
}

function Invoke-Doctor {
    Assert-Initialized
    $config = Read-Config
    $tasks = @(Read-JsonArray -Path $script:TasksPath)
    $noteList = @(Read-JsonArray -Path $script:NotesPath)
    $issues = New-Object System.Collections.Generic.List[string]
    if ([int]$config.version -ne 1) { $issues.Add("Unsupported config version: $($config.version)") }
    foreach ($task in $tasks) {
        try { [void](Parse-DateValue -Value ([string]$task.date)) } catch { $issues.Add("Task $($task.id): $($_.Exception.Message)") }
        if ($task.priority -notin @('P0', 'P1', 'P2', 'P3')) { $issues.Add("Task $($task.id): invalid priority $($task.priority)") }
        if ($task.status -notin @('todo', 'in-progress', 'blocked', 'done', 'cancelled')) { $issues.Add("Task $($task.id): invalid status $($task.status)") }
        if (($task.start -and -not $task.end) -or ($task.end -and -not $task.start)) { $issues.Add("Task $($task.id): incomplete time range") }
    }
    $duplicateIds = @($tasks | Group-Object id | Where-Object Count -gt 1)
    foreach ($group in $duplicateIds) { $issues.Add("Duplicate task ID: $($group.Name)") }
    $calendar = Sync-AllCalendars
    Write-Output "Workflow home: $script:WorkflowHome"
    Write-Output "Config version: $($config.version); tasks: $($tasks.Count); notes: $($noteList.Count)"
    Write-Output "Calendar records: $($calendar.count)"
    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) { Write-Error $issue }
        throw "Doctor found $($issues.Count) issue(s)."
    }
    Write-Output 'Doctor: OK'
}

switch ($Action) {
    'init' { Initialize-Workflow }
    'doctor' { Invoke-Doctor }
    'add-task' { Add-Task }
    'update-task' { Update-Task }
    'list' { List-Tasks }
    'add-note' { Add-WorkflowNote }
    'inspect' { Inspect-Workflow }
    'calendar' {
        Assert-Initialized
        $rangeFrom = if ($From) { Parse-DateValue -Value $From -Name 'From' } else { $null }
        $rangeTo = if ($To) { Parse-DateValue -Value $To -Name 'To' } else { $null }
        if ($rangeFrom -and $rangeTo -and $rangeTo -lt $rangeFrom) { throw 'To must not be earlier than From.' }
        $calendar = Write-CalendarFiles -Tasks @(Read-JsonArray -Path $script:TasksPath) -RangeFrom $rangeFrom -RangeTo $rangeTo
        Write-Output "Calendar Markdown: $($calendar.markdown)"
        Write-Output "Calendar ICS: $($calendar.ics)"
        Write-Output "Events: $($calendar.count)"
    }
    'daily-report' { New-DailyReport }
    'weekly-report' { New-WeeklyReport }
}
