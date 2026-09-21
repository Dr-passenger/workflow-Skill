---
name: minimax-h3-pet-live-wallpaper
description: Create seamless pet live-wallpaper videos from a user-supplied pet photo with fifteen bundled 16:9 indoor and secure outdoor home backgrounds. Use MiniMax-H3 in full-reference Ref2VA mode, submit the pet and scene as ordered reference images, write the official six-section Ref2VA prompt, preserve pet identity and scene layout, poll the task, download the MP4, and quality-check the loop.
---

# 萌宠动态桌面 Ref2VA 工作流

把用户上传的萌宠照片与内置家庭场景组合，并用 `MiniMax-H3` 的 Ref2VA 路径生成 16:9 可循环桌面壁纸。坚持单镜头、锁定机位、轻量动作和近似首尾姿态，降低身份漂移、闪烁和循环跳变。

## 输入与默认值

- 必需：一张主体清晰的萌宠照片。若用户未上传，先请求上传，不得伪造宠物身份。
- 可选：场景编号 `01`–`15`；未指定时，根据毛色、动作空间、室内/室外偏好和整体明暗选择最合适的场景。
- 默认：8 秒、16:9、2K、单镜头、静止相机、无对白无音乐。
- 草稿：用户明确接受较低分辨率或希望先省成本试片时，使用 480P（烟测档）。
- API 密钥：仅从本机环境变量 `MINIMAX_API_KEY` 读取。不得要求用户在聊天中粘贴密钥，也不得把密钥写入文件或命令历史。

## 固定模型与输入映射

- 工作流变体：`H3-Base-Ref2VA`（全参考模式）。
- 托管 API 的 `model` 字段：`MiniMax-H3`。不要把 API 字段改成不存在的 `MiniMax-H3-Ref2VA`。
- `<Picture 1>`：用户上传的萌宠照片，作为 `<Subject 1>` 的唯一身份参考。
- `<Picture 2>`：选中的成品背景，作为 `<Subject 2>` 的环境、布局、光照与构图参考。
- 两张图片都以 `role=reference_image` 提交。不得出现 `first_frame` 或 `last_frame`，也不得把帧模式与参考模式混用。

## 资源导航

- 场景、背景生成词、Ref2VA 六段式提示词模板：读取 `references/scene-presets.json`。
- MiniMax H3 接口、Ref2VA 格式和限制：需要提交或排错时读取 `references/minimax-h3-api.md`。
- 十五张成品背景：使用 `assets/backgrounds/`，其中 `01`–`10` 为室内、`11`–`15` 为安全室外场景。
- 提交、轮询、下载：运行 `scripts/minimax_h3_wallpaper.py`。
- 资产和提示词结构检查：运行 `scripts/validate_assets.py`。

## 工作流

### 1. 检查宠物照片

使用图像查看工具检查照片。确认：

- 只有一个主要宠物，脸部、眼睛、毛色纹路和四肢尽量清楚。
- 图片不是严重模糊、过曝、极端裁切或被大面积遮挡。
- 对猫狗以外宠物，删除场景词中不合适的跑跳动作并改为安全、物种合理的动作。

记录身份锚点：物种/品种特征、毛色与纹路、脸型、眼睛颜色、耳朵、尾巴、体型、项圈或衣物。除非用户要求，不添加项圈、衣物或新配饰。

### 2. 选择场景

读取 `references/scene-presets.json`，按编号匹配背景、`setting_notes_en` 和 `action_en`。选择标准：

- 深色宠物优先明亮场景；浅色宠物优先中深色场景，保证轮廓分离。
- 活泼宠物优先厨房、游戏房、阁楼或工作室；安静宠物优先雨窗、榻榻米或月夜卧室。
- 室外场景只使用围栏后院、封闭庭院或安全露台；始终保留关闭的门、完整围栏和远离边界的活动区。
- 桌面图标较多时，优先有干净边缘或暗角的场景。

不得让模型自行替换背景布局、加入其他宠物或人物。

### 3. 编写 Ref2VA 提示词

严格使用官方六段式顺序，字段名不得翻译或改名：

1. `subject_definitions`
2. `summary`
3. `retention_analysis`
4. `detailed_description`
5. `overall_soundscape`
6. `non_diegetic_music`

本工作流将宠物抽象为 `<Subject 1>`、场景抽象为 `<Subject 2>`。图片只用于定义主体与环境，不作为具体关键帧，因此不要额外声明独立的 `<Picture N>` 关键帧条目。`summary` 使用 `[reference generation]`；`retention_analysis` 对两个主体都使用 `fully_preserved`；`detailed_description` 采用单个 `[Shot 1]`，完整描述构图、身份、环境、动作、机位、循环回位和同步声音。

从所选场景的 `setting_notes_en`、`action_en` 与顶层 `ref2va_prompt_template_en` 组装提示词，只做必要改动：

- 用照片中可见的真实身份锚点补充 `<Subject 1>`，不要猜测看不清的特征。
- 动作不符合物种或身体条件时，降级为轻走、嗅闻、拨球、探头、伸展或趴下。
- 始终保留静止机位、单镜头、首尾近似、自然接触阴影、无额外动物、无形变/重复肢体/闪烁/文字/标识。
- 桌面壁纸以低到中等运动幅度为主，避免快速摇镜、推拉、频繁跳跃和遮满画面。

### 4. 提交前确认成本

MiniMax H3 是计费服务。首次实际提交前，向用户清楚说明分辨率与时长，并取得继续生成的确认。只做素材准备、提示词预览或 `--dry-run` 不需要确认。

### 5. 运行

Ref2VA 双参考图模式：

```powershell
python scripts/minimax_h3_wallpaper.py --scene 01 --pet "C:\path\pet.jpg" --output "C:\path\pet-wallpaper.mp4"
```

先预览完整六段式提示词与请求，但不联网、不计费：

```powershell
python scripts/minimax_h3_wallpaper.py --scene 01 --pet "C:\path\pet.jpg" --dry-run
```

使用自定义背景：

```powershell
python scripts/minimax_h3_wallpaper.py --scene 01 --pet "C:\path\pet.jpg" --background "C:\path\room.png" --dry-run
```

使用官方 Context-IR 再优化提示词时加 `--context-ir`。它会额外产生调用与费用；仅在用户同意后启用。Context-IR 返回的新提示词仍应保持 Ref2VA 六段式结构。

### 6. 质量检查与单点迭代

检查输出：

- 身份：脸型、毛色纹路、眼睛、耳尾和体型与 `<Picture 1>` 一致。
- 解剖：四肢数量正确，无粘连、穿模、复制或突然消失。
- 场景：家具、光线、透视和镜头位置与 `<Picture 2>` 稳定一致，无新增人物或动物。
- 循环：比较第一秒与最后一秒；宠物位置、姿态、球/玩具位置及照明变化尽量接近。
- 桌面体验：运动不抢眼，画面边缘保留可用空间，无文字、标识或水印。

每次只改一个问题：身份漂移时加强 `<Subject 1>` 的可见身份锚点；动作过大时降低运动幅度；循环跳变时简化动作并要求在最后 1 秒回到起始姿态；背景漂移时加强 `<Subject 2>` 的 `fully_preserved` 约束。

## 输出

交付 MP4、所用场景编号、最终六段式 Ref2VA 提示词、分辨率、时长和输入映射。明确保存路径。若只完成了素材和请求预览，说明尚未调用计费 API。
