---
name: minimax-h3-pet-art-frame
description: 将用户上传的 1–3 只真实宠物照片制作成固定机位的动态艺术相框，并通过用户自行部署在远程环境的 MiniMax-H3 生成表情循环 Ref2VA、汽车左转惯性 FL2VA、汽车右转惯性 FL2VA 三种 8 秒视频；不调用 MiniMax 官方公共 API。适用于萌宠车机相框、桌面相框、循环屏保、私有部署、宠物身份保持、多宠物合成、首尾帧一致，以及乡村田园、欧洲小镇、科幻、赛博朋克或极简纯白写实场景。
---

# MiniMax-H3 萌宠动态艺术相框

## 概览

把 1–3 张宠物身份照和一个内置生活化相框背景先合成为唯一静态关键帧，再为用户自行部署的远程 MiniMax-H3 生成三条 8 秒视频任务。宠物可以动，但相框、背景、机位、光照和非宠物物体必须保持静止。不得调用 MiniMax 官方公共 API；远程传输、鉴权和推理由部署方 runner 负责。

必须把“合成关键帧”作为独立步骤。不要直接让视频模型把彼此分离的宠物照片和空背景临时拼成画面，否则更容易出现身份混合、比例漂移、宠物互相穿插和场景穿模。

## 输入与输出

输入：

- 1–3 张宠物照片，每张只指定一只身份主体；支持 JPG、JPEG、PNG、WEBP、HEIC、HEIF。
- 优先使用脸部、耳朵、毛色花纹清晰，无遮挡、无运动模糊的照片。
- 用户选择一个场景；未指定时展示五个预设并让用户选择，不擅自混合场景。
- 若宠物原图只有半身或局部，不虚构被裁掉的完整身体；合成时沿用自然局部构图。

输出：

- 一张 16:9 合成关键帧 PNG。
- 三条 8 秒 MP4：`expression-loop`、`left-inertia`、`right-inertia`。
- 对应的 Ref2VA/FL2VA 完整提示词与生成参数，便于复现。

## 五个生活化相框

预设、装扮规则和素材路径以 `references/frame-presets.json` 为准：

1. 乡村田园农舍：写实农舍、香草花园和草地；仅可增加低遮挡亚麻或细格纹领巾。
2. 欧洲小镇街角：写实老城步行街和石板路；仅可增加小号粗花呢领结或窄领巾。
3. 科幻观景生活舱：写实近未来居住舱；仅可增加轻量银灰项圈或低轮廓胸背，不用头盔和盔甲。
4. 赛博朋克雨夜公寓：安全、干燥的写实室内，窗外是霓虹雨夜；仅可增加带微弱青紫灯边的低轮廓项圈或胸背，不改造宠物身体。
5. 极简纯白写实：纯白背景，只有底部一条均匀黑边；完全保留现实外观，不新增服饰、风格化、品牌标识或车机界面。

装扮不能遮挡脸、眼睛、耳朵或身份花纹；若与宠物原有项圈或衣服冲突，以原图为准且不新增。

## 三种视频模式

| 输出 | MiniMax-H3 模式 | 允许的宠物动作 | 端点规则 |
|---|---|---|---|
| 表情循环 | Ref2VA | 身体与接触点不动，仅眼睑、视线、耳尖小角度、鼻子、胡须、嘴角做自然微表情 | 8.00 秒恢复 0.00 秒全部可动特征 |
| 左转惯性 | FL2VA | 模拟车辆左转，宠物因惯性向画面右侧小幅倾斜，回正后轻微反向过冲 | 同一关键帧同时作为首帧和尾帧 |
| 右转惯性 | FL2VA | 模拟车辆右转，宠物因惯性向画面左侧小幅倾斜，回正后轻微反向过冲 | 同一关键帧同时作为首帧和尾帧 |

所有模式都必须使用单一固定全景机位。禁止推拉摇移、跟拍、变焦、重构图、景深漂移、曝光跳变、视差和背景动画。背景中的雨、灯光、星球、植物、家具、反射等都视为静态画面元素。

## 工作流

### 1. 检查身份照片

逐只记录可见身份锚点：物种与品种特征、脸型、眼睛、耳朵、鼻口、毛色和花纹边界、尾巴、身材比例、年龄感及已有配饰。多宠物时固定照片顺序，后续 `<Picture 1>`、`<Picture 2>`、`<Picture 3>` 始终对应同一身份。

发现脸被遮住、分辨率过低或宠物无法区分时，先请求更清晰照片。不要用另一只宠物的花纹补全它。

### 2. 生成静态合成关键帧

先运行：

```powershell
python scripts/minimax_h3_art_frame.py --frame 01 --pet C:\path\pet1.png --pet C:\path\pet2.png --print-composite-prompt
```

按输出的 `input_order` 将所有宠物身份照依次提供给图像生成器，最后提供所选 `assets/frames/*.png` 背景，再使用输出的合成提示词。必须使用内置背景的原始 16:9 全景构图，不裁掉边框或底部黑边。

检查合成结果：每只宠物身份清楚且不串脸；大小合理；轮廓彼此分离；四肢与接触阴影正常；衣着符合当前场景且不遮挡身份；宠物和地面、家具、边框无穿插。若不合格，只修正合成关键帧，不进入视频步骤。

### 3. 预检三种远程任务

```powershell
python scripts/minimax_h3_art_frame.py `
  --frame 01 `
  --pet C:\path\pet1.png `
  --pet C:\path\pet2.png `
  --keyframe C:\path\composite.png `
  --mode all `
  --dry-run
```

确认三点：

- `expression-loop` 只使用 `reference_image`：原始宠物身份照在前，合成关键帧在最后。
- 两个惯性模式只使用 `first_frame` 和 `last_frame`，且两者都是同一张合成关键帧。
- 不得在同一请求中混用 `reference_image` 与首尾帧角色。

提示词格式、任务清单与私有 runner 契约见 `references/remote-runtime.md`。时间轴、静态约束和五套装扮规则由 `references/frame-presets.json` 集中维护。

### 4. 导出任务或调用私有 runner

未提供 runner 时只导出三份 JSON 任务清单，不发起网络请求：

```powershell
python scripts/minimax_h3_art_frame.py `
  --frame 01 `
  --pet C:\path\pet1.png `
  --pet C:\path\pet2.png `
  --keyframe C:\path\composite.png `
  --mode all `
  --export-dir C:\path\jobs `
  --output-dir C:\path\output
```

部署方已有适配程序时显式传入 runner：

```powershell
python scripts/minimax_h3_art_frame.py `
  --frame 01 `
  --pet C:\path\pet1.png `
  --pet C:\path\pet2.png `
  --keyframe C:\path\composite.png `
  --mode all `
  --export-dir C:\path\jobs `
  --output-dir C:\path\output `
  --runner python `
  --runner-arg C:\private-deployment\run_h3_job.py `
  --runner-arg=--job `
  --runner-arg="{manifest}"
```

runner 读取任务清单，把本地路径上传或映射到远程环境，再按角色调用私有模型并把结果写入 `output_path`。不要把远程地址、令牌或私有 SDK 凭据写进 Skill；它们只属于部署方适配程序。默认输出 2K，也可加 `--resolution 768P`。本 Skill 固定为 8 秒，不接受其他时长。

### 5. 逐条验收

逐帧检查，不能只看封面：

- 三只宠物以内均不串脸、不融合、不新增、不消失，花纹和配饰始终属于正确身份。
- 宠物无多肢、断肢、浮脚、脚底滑动、身体拉伸、互相碰撞、穿过地面或边框。
- 表情循环中身体与接触点不动，表情丰富但保持动物本身的解剖与行为，不做人脸式夸张表演。
- 左转时惯性朝画面右侧，右转时朝画面左侧；位移幅度小，支撑点不滑动，软毛和低轮廓配饰只做轻微滞后。
- 相框、全景背景、所有背景物体和机位从头到尾静止。
- 0.00 秒与 8.00 秒视觉一致；惯性片不能以硬切、溶解、变形或突然冻结伪造回归。

若失败，只重做对应模式。优先减小动作幅度、拉开宠物间距或回到合成关键帧修复接触关系，不用更大的运动掩盖问题。

## 维护与校验

修改预设或素材后运行：

```powershell
python scripts/validate_assets.py
```

该校验器检查五张 PNG、16:9 比例、1–3 只宠物的提示词结构、Ref2VA/FL2VA 端点规则、静态背景约束和左右惯性方向。
