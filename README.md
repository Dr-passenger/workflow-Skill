# Manage Workflow for OpenCode
作者：杨淇竣
`manage-workflow` 是一个本地优先的 OpenCode 工作流 Skill，用于管理研发与模型训练相关的日常任务、临时安排、日程和工作汇报。

## 功能

- 管理每日任务、优先级、时间段、状态和执行结果
- 插入临时或紧急事项，并检测时间冲突
- 检视 Git 仓库、Python/Conda、GPU、训练进程和模型结果文件
- 生成每日工作汇报
- 生成每周任务和工作流复盘
- 自动维护 Markdown 日程表和标准 `.ics` 日历
- 使用本地 JSON 文件保存数据，不依赖云端数据库

每日汇报固定覆盖：

1. 当日任务安排与执行
2. 代码与训练环境检视
3. 模型运行结果
4. 问题、阻塞与决策
5. 次日任务预备

## 仓库内容

```text
manage-workflow/
├── SKILL.md
├── references/
│   ├── inspection.md
│   └── reporting.md
└── scripts/
    └── workflow.ps1

manage-workflow-opencode.zip
README.md
```

## 环境要求

- OpenCode 支持 Agent Skills 的版本
- Windows PowerShell 5.1 或 PowerShell 7
- Linux/macOS 使用时需要安装 PowerShell 7，并用 `pwsh` 替换示例中的 `powershell`
- Git、Python、Conda、NVIDIA 工具均为可选；Skill 只检视实际存在的工具

## 部署到 Windows 系统电脑

### 方法一：使用 ZIP 包

1. 下载仓库中的 `manage-workflow-opencode.zip`。
2. 打开 PowerShell，执行：

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.config\opencode\skills"

Expand-Archive `
  -LiteralPath "D:\Downloads\manage-workflow-opencode.zip" `
  -DestinationPath "$env:USERPROFILE\.config\opencode\skills" `
  -Force
```

安装完成后应存在：

```text
%USERPROFILE%\.config\opencode\skills\manage-workflow\SKILL.md
```

### 方法二：使用 Git

克隆本仓库，然后将 `manage-workflow` 目录复制到 OpenCode 全局 Skill 目录：

```powershell
$repoUrl = "https://github.com/OWNER/REPOSITORY.git"
$skillTarget = "$env:USERPROFILE\.config\opencode\skills\manage-workflow"

git clone $repoUrl manage-workflow-repo

New-Item -ItemType Directory -Force $skillTarget

Copy-Item `
  -Path ".\manage-workflow-repo\manage-workflow\*" `
  -Destination $skillTarget `
  -Recurse `
  -Force
```

## 安装到 Linux 或 macOS

需要先安装 PowerShell 7。然后执行：

```bash
mkdir -p ~/.config/opencode/skills
unzip manage-workflow-opencode.zip -d ~/.config/opencode/skills
```

运行脚本时，Skill 会使用 `pwsh`：

```bash
pwsh -NoProfile -File ~/.config/opencode/skills/manage-workflow/scripts/workflow.ps1 \
  -Action doctor \
  -WorkflowHome /path/to/workflow-home
```

## 项目级安装

如果只希望在单个项目中使用，将目录放到：

```text
<项目目录>/.opencode/skills/manage-workflow/SKILL.md
```

OpenCode 官方支持以下 Skill 位置：

- 全局：`~/.config/opencode/skills/<name>/SKILL.md`
- 项目：`.opencode/skills/<name>/SKILL.md`

参考：[OpenCode Agent Skills](https://opencode.ai/docs/skills)。

## 第一次初始化

重新打开 OpenCode 或开始一个新会话，然后输入：

```text
请加载 manage-workflow Skill。

在 D:\Work\workflow-home 初始化我的工作流台账。
代码仓库包括：
- D:\Work\project-a
- D:\Work\project-b

模型运行结果主要位于：
- D:\Work\project-a\outputs\metrics.json
- D:\Work\project-a\runs\*\result.json

工作时间为 09:00-18:00，时区为 Asia/Shanghai。
完成初始化后检查配置和日程文件。
```

建议使用一个独立、稳定的目录作为工作流台账，例如：

```text
D:\Work\workflow-home
```

不要把台账放进 Skill 安装目录，否则升级 Skill 时可能混入用户数据。

## 设置默认台账位置

从同一个 PowerShell 会话启动 OpenCode：

```powershell
$env:WORKFLOW_HOME = "D:\Work\workflow-home"
opencode
```

以后可以直接说“安排今天的工作”或“生成本周复盘”，无需重复台账路径。

## 常用提示词

### 安排今日任务

```text
使用 manage-workflow 安排今天的工作。
检查未完成和阻塞任务，检视代码、训练环境和最新模型结果，
然后按照优先级生成今天的时间安排。
```

### 插入临时事项

```text
使用 manage-workflow 插入临时任务：
今天 14:00-15:00 排查 project-a 的显存溢出问题，优先级 P0。
检查时间冲突，必要时调整低优先级任务。
```

### 更新任务和模型结果

```text
将“训练基线模型”标记为完成。
结果：run-042，val_loss=0.184，F1=0.912，checkpoint=epoch_12。
```

### 生成日报

```text
使用 manage-workflow 生成今天的工作汇报。
覆盖任务安排、代码与训练环境检视、模型结果、问题与决策、次日预备。
没有证据的内容明确标记为“未采集”或“未记录”。
```

### 生成周报

```text
使用 manage-workflow 梳理本周任务与工作流。
汇总完成、阻塞、结转和临时任务，分析实验结果、工作流瓶颈，
并生成下周 P0/P1 任务。
```

### 查看日程

```text
使用 manage-workflow 显示未来七天日程并检查时间冲突。
```

## 工作流数据

初始化后，台账目录包含：

| 路径 | 用途 |
|---|---|
| `config.json` | 仓库、工作时间、训练进程和模型结果路径配置 |
| `tasks.json` | 任务账本 |
| `notes.json` | 模型结果、风险、决策和工作记录 |
| `calendar/schedule.md` | Markdown 日程表 |
| `calendar/schedule.ics` | 可导入日历应用的 ICS 文件 |
| `snapshots/` | 代码和训练环境检视快照 |
| `reports/daily/` | 每日工作汇报 |
| `reports/weekly/` | 每周任务与工作流梳理 |

`tasks.json` 和 `notes.json` 是事实来源。不要直接修改自动生成的日历文件。

## OpenCode 未发现 Skill

检查：

1. 文件名是否为大写的 `SKILL.md`
2. 目录名是否为 `manage-workflow`
3. 是否重新打开了 OpenCode 会话
4. 当前 Agent 是否允许使用 `skill`、Shell、读取和编辑工具

必要时在 `opencode.json` 中允许该 Skill：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "skill": {
      "manage-workflow": "allow"
    }
  }
}
```

然后输入：

```text
请加载名为 manage-workflow 的 Skill，并检查工作流台账。
```

部分 OpenCode V2 版本会把 Skill 显示为斜杠命令：

```text
/manage-workflow 帮我安排今天的任务
```

## 安全说明

- 所有任务、快照和报告默认只保存在本地台账目录
- 环境检视保持只读，不会自动启动训练、升级依赖或清理工作区
- 报告不会读取或保存 `.env`、访问令牌和密码等敏感内容
- 模型运行健康状态必须由日志、指标或 checkpoint 等证据确认
