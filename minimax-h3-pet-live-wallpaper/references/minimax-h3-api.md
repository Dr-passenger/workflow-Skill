# MiniMax H3 Ref2VA API notes

Verified against the official international documentation and the official MiniMax-H3 prompt-writing guide on 2026-09-21.

## Model identity

- Open-model task family: `H3-Base-Ref2VA`.
- Hosted API model value: `MiniMax-H3`.
- Hosted input mode: reference-to-video, selected by `role=reference_image`, `reference_video`, or `reference_audio` content items.

Do not send `model: "MiniMax-H3-Ref2VA"`; that is not a hosted API model value. This skill sends `model: "MiniMax-H3"` and selects Ref2VA by using only reference roles.

## Endpoints

- Create video: `POST https://api.minimax.io/v2/video_generation`
- Create Context-IR prompt-enhancement task: `POST https://api.minimax.io/v2/h3_context_ir`
- Query either task: `GET https://api.minimax.io/v2/query/video_generation/{task_id}`

Authentication uses `Authorization: Bearer <API_KEY>`. Keep the key in `MINIMAX_API_KEY` and never put it in a project file.

Official sources:

- [Create Video Generation Task](https://platform.minimax.io/docs/api-reference/video-generation-v2-create)
- [Create H3-Context-IR Task](https://platform.minimax.io/docs/api-reference/video-generation-v2-h3-context-ir)
- [Query Task](https://platform.minimax.io/docs/api-reference/video-generation-v2-query)
- [MiniMax-H3 official repository](https://github.com/MiniMax-AI/MiniMax-H3)
- [Official Ref2VA prompt format guide](https://github.com/MiniMax-AI/MiniMax-H3/blob/main/skills/h3-prompt-writing/references/ref-en.txt)

## Ref2VA request mapping

The content array order defines the picture labels used in the prompt:

1. The pet image is the first `reference_image`, so it is `<Picture 1>` and defines `<Subject 1>`.
2. The background image is the second `reference_image`, so it is `<Picture 2>` and defines `<Subject 2>`.

```json
{
  "model": "MiniMax-H3",
  "content": [
    { "type": "text", "text": "subject_definitions:\n..." },
    {
      "type": "image_url",
      "image_url": { "url": "data:image/jpeg;base64,..." },
      "role": "reference_image"
    },
    {
      "type": "image_url",
      "image_url": { "url": "data:image/png;base64,..." },
      "role": "reference_image"
    }
  ],
  "resolution": "2K",
  "duration": 8,
  "ratio": "16:9"
}
```

Image-to-video and reference-to-video are mutually exclusive. Never include `first_frame` or `last_frame` in this workflow.

## Official Ref2VA prompt structure

Write all six sections in English and preserve this exact order and field spelling:

```text
subject_definitions:
...

summary:
[reference generation] ...

retention_analysis:
<Subject 1> (appears in [Shot 1]): fully_preserved - ...
<Subject 2> (appears in [Shot 1]): fully_preserved - ...

detailed_description:
The target video uses ...
[Shot 1] ...

overall_soundscape:
...

non_diegetic_music:
N/A
```

Use `<Subject N>` for reusable visible content such as the pet and environment. Because both pictures only define subjects in this workflow and are not concrete first/key/last frames, cite `<Picture 1>` and `<Picture 2>` inside the corresponding subject definitions rather than creating standalone picture entries. Keep every label's meaning consistent across all six sections.

For generation tasks, the official guide normally targets a detailed 350–500 English-word `detailed_description`. A single shot still needs explicit composition, subject appearance and position, environment and lighting, action and state changes, camera behavior, current sound, and where references take effect. This workflow also inserts a fixed 8-second action timeline, scene-specific safe zone, solid collision boundaries, visible prop clearance, material-aware ground response, a closed ambient cycle, state restoration, and matching 0.00/8.00-second loop anchors.

## Current request limits

- Resolution: `768P` or `2K` for `MiniMax-H3`.
- Duration: the API accepts integer `4`–`15` seconds, but this workflow deliberately fixes every request to `8` seconds so its action and return timing remain valid.
- Ratio: Ref2VA accepts `adaptive`, `21:9`, `16:9`, `4:3`, `1:1`, `3:4`, or `9:16`; use `16:9` for desktop wallpaper.
- Images: JPG/JPEG/PNG/WEBP/HEIC/HEIF, at most 30 MB each, dimensions 256–5760 px, aspect ratio 0.4–2.5, up to nine reference images.
- Entire JSON request: at most 64 MB. Prefer public URLs for large media; this skill uses Base64 data URIs for ordinary local photos and bundled backgrounds.

Every request must include a non-empty text item. The create call returns `task_id`; poll until `task.status` is `succeeded`, then read the video URL from `task.content.url`.

## Context-IR

Context-IR returns a rewritten prompt rather than a video. It accepts the same multimodal content relationship, duration, and ratio, then exposes the result in `task.content.prompt`. Reuse that prompt as the text item for the video-generation call. Because it is a separate paid call, enable it only after user approval. For Ref2VA, the rewritten result should retain the official six sections and consistent reference labels.

## Compatibility fallback

The bundled script tries the documented V2 query route first. If a compatible gateway returns HTTP 404, it can fall back to the older `GET /v1/query/video_generation?task_id=...` plus `GET /v1/files/retrieve?file_id=...` flow. Do not prefer that fallback over the current official V2 contract.
