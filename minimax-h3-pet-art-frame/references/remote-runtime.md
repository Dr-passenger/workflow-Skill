# 私有远程 MiniMax-H3 运行约定

本 Skill 只面向用户自行部署的 MiniMax-H3，不调用 MiniMax 官方公共 API，不读取 `MINIMAX_API_KEY`，也不内置任何官方服务 URL。

## 模式分离

- `expression-loop` 使用 Ref2VA：按顺序提供 1–3 张宠物身份照，最后提供合成关键帧，全部标为 `reference_image`。
- `left-inertia` 与 `right-inertia` 使用 FL2VA：把同一合成关键帧分别标为 `first_frame` 和 `last_frame`。
- 不在同一个任务中混合 `reference_image` 与 `first_frame`/`last_frame`。

## 提示词结构

Ref2VA 按以下顺序输出：

1. `subject_definitions`
2. `summary`
3. `retention_analysis`
4. `detailed_description`
5. `overall_soundscape`
6. `non_diegetic_music`

FL2VA 先声明首尾图与 0.00/8.00 秒的对齐关系，再输出：

1. `integrated_multimodal_description`
2. `overall_soundscape`
3. `non_diegetic_music`

## 任务清单格式

`scripts/minimax_h3_art_frame.py` 输出与传输协议无关的 JSON。核心字段示例：

```json
{
  "schema_version": 1,
  "runtime": "user-managed-remote-deployment",
  "model": "MiniMax-H3",
  "pipeline": "Ref2VA",
  "mode": "expression-loop",
  "duration_seconds": 8,
  "resolution": "2K",
  "ratio": "16:9",
  "prompt": "<完整提示词>",
  "inputs": [
    {"picture": 1, "role": "reference_image", "path": "<本地或挂载路径>"}
  ],
  "output_path": "<期望 MP4 路径>",
  "transport": {
    "kind": "external_runner",
    "official_minimax_api": false
  }
}
```

## 远程适配器契约

部署方提供一个可执行程序作为 runner。脚本会把任务 JSON 文件路径传给 runner；runner 负责：

1. 读取任务清单。
2. 将 `inputs[].path` 上传到远程环境，或映射为远程可见的共享存储路径。
3. 按 `picture` 顺序和 `role` 绑定模型输入。
4. 将 `prompt`、`pipeline`、8 秒时长、分辨率及画幅转换为该部署的实际推理参数。
5. 等待推理完成，并把视频保存到 `output_path`。
6. 成功时退出码为 0；失败时返回非零退出码并把错误写入标准错误。

runner 的接口、鉴权和地址均由部署方维护，不写入本 Skill。调用示例：

```powershell
python scripts/minimax_h3_art_frame.py `
  --frame 01 `
  --pet C:\path\pet.png `
  --keyframe C:\path\composite.png `
  --mode all `
  --runner python `
  --runner-arg C:\private-deployment\run_h3_job.py `
  --runner-arg=--job `
  --runner-arg="{manifest}"
```

若 `--runner-arg` 中没有 `{manifest}`，脚本会自动把任务清单路径作为最后一个参数。还可使用 `{output}`、`{mode}` 和 `{pipeline}` 占位符。

在获得部署环境的实际命令、请求协议或 SDK 后，只修改 runner，不改动场景素材和提示词生成逻辑。
