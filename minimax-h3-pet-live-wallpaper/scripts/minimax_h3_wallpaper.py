#!/usr/bin/env python3
"""Submit a MiniMax-H3 Ref2VA pet live-wallpaper job and download the MP4."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
PRESETS_PATH = SKILL_DIR / "references" / "scene-presets.json"
DEFAULT_BASE_URL = "https://api.minimax.io"
MAX_IMAGE_BYTES = 30 * 1024 * 1024
MAX_REQUEST_BYTES = 64 * 1024 * 1024
TERMINAL_FAILURES = {"failed", "failure", "cancelled", "canceled"}


class HttpStatusError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def load_presets() -> dict[str, Any]:
    with PRESETS_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def get_scene(presets: dict[str, Any], scene_id: str) -> dict[str, Any]:
    normalized = scene_id.zfill(2)
    for scene in presets["scenes"]:
        if scene["id"] == normalized or scene["slug"] == scene_id:
            return scene
    available = ", ".join(scene["id"] for scene in presets["scenes"])
    raise ValueError(f"Unknown scene '{scene_id}'. Available scene IDs: {available}")


def resolve_input(path_value: str, label: str) -> Path:
    path = Path(path_value).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"{label} file not found: {path}")
    size = path.stat().st_size
    if size > MAX_IMAGE_BYTES:
        raise ValueError(f"{label} is {size / 1024 / 1024:.1f} MB; MiniMax H3 allows 30 MB per image")
    return path


def image_data_uri(path: Path) -> str:
    mime, _ = mimetypes.guess_type(path.name)
    aliases = {"image/jpg": "image/jpeg"}
    mime = aliases.get(mime or "", mime)
    allowed = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}
    if mime not in allowed:
        raise ValueError(f"Unsupported image format for {path.name}: {mime or 'unknown'}")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def build_prompt(
    presets: dict[str, Any],
    scene: dict[str, Any],
    duration: int,
    prompt_extra: str | None,
) -> str:
    templates = presets["ref2va_prompt_template_en"]
    section_order = presets["ref2va_section_order"]
    extra_direction = ""
    if prompt_extra and prompt_extra.strip():
        extra_direction = "Additional user direction: " + prompt_extra.strip()
    values = {
        "duration": duration,
        "setting_notes": scene["setting_notes_en"],
        "action": scene["action_en"],
        "extra_direction": extra_direction,
    }
    prompt = "\n\n".join(
        f"{section}:\n{templates[section].format(**values).strip()}" for section in section_order
    )
    if len(prompt) > 7000:
        raise ValueError("Final prompt exceeds the MiniMax H3 7000-character limit")
    return prompt


def build_payload(
    presets: dict[str, Any],
    scene: dict[str, Any],
    args: argparse.Namespace,
) -> tuple[dict[str, Any], dict[str, Any]]:
    if not args.pet:
        raise ValueError("--pet is required for the Ref2VA workflow")
    pet = resolve_input(args.pet, "Pet image")
    background_value = args.background or str(SKILL_DIR / scene["background"])
    background = resolve_input(background_value, "Background image")
    inputs = [
        (pet, "reference_image", "<Picture 1>", "pet identity"),
        (background, "reference_image", "<Picture 2>", "home environment"),
    ]

    prompt = build_prompt(presets, scene, args.duration, args.prompt_extra)
    content: list[dict[str, Any]] = [{"type": "text", "text": prompt}]
    summary_inputs: list[dict[str, str]] = []
    for image_path, role, ref_label, purpose in inputs:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": image_data_uri(image_path)},
                "role": role,
            }
        )
        summary_inputs.append(
            {"file": str(image_path), "role": role, "ref_label": ref_label, "purpose": purpose}
        )

    payload = {
        "model": presets["api_model"],
        "content": content,
        "resolution": args.resolution,
        "duration": args.duration,
        "ratio": args.ratio,
    }
    body_size = len(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
    if body_size > MAX_REQUEST_BYTES:
        raise ValueError(
            f"Request body is {body_size / 1024 / 1024:.1f} MB; maximum is 64 MB. "
            "Use smaller images or public URLs."
        )
    summary = {
        "scene": {"id": scene["id"], "title_zh": scene["title_zh"], "slug": scene["slug"]},
        "mode": presets["input_mode"],
        "model": payload["model"],
        "model_variant": presets["model_variant"],
        "resolution": args.resolution,
        "duration": args.duration,
        "ratio": args.ratio,
        "context_ir": bool(args.context_ir),
        "inputs": summary_inputs,
        "estimated_request_mb": round(body_size / 1024 / 1024, 2),
        "prompt": prompt,
    }
    return payload, summary


def request_json(
    method: str,
    url: str,
    api_key: str,
    payload: dict[str, Any] | None = None,
    timeout: int = 180,
) -> dict[str, Any]:
    data = None
    headers = {"Authorization": f"Bearer {api_key}"}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise HttpStatusError(exc.code, f"MiniMax HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"MiniMax network error: {exc.reason}") from exc
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"MiniMax returned non-JSON data from {url}") from exc


def query_current(base_url: str, api_key: str, task_id: str) -> dict[str, Any]:
    encoded_id = urllib.parse.quote(task_id, safe="")
    return request_json("GET", f"{base_url}/v2/query/video_generation/{encoded_id}", api_key)


def query_legacy(base_url: str, api_key: str, task_id: str) -> dict[str, Any]:
    query = urllib.parse.urlencode({"task_id": task_id})
    return request_json("GET", f"{base_url}/v1/query/video_generation?{query}", api_key)


def poll_task(
    base_url: str,
    api_key: str,
    task_id: str,
    poll_interval: float,
    timeout_seconds: int,
) -> tuple[dict[str, Any], bool]:
    deadline = time.monotonic() + timeout_seconds
    use_legacy = False
    last_status = ""
    while time.monotonic() < deadline:
        try:
            response = (
                query_legacy(base_url, api_key, task_id)
                if use_legacy
                else query_current(base_url, api_key, task_id)
            )
        except HttpStatusError as exc:
            if exc.status == 404 and not use_legacy:
                use_legacy = True
                continue
            raise

        if use_legacy:
            status = str(response.get("status", "")).strip().lower()
            base_resp = response.get("base_resp") or {}
            if base_resp.get("status_code") not in (None, 0):
                raise RuntimeError(f"MiniMax task query failed: {base_resp}")
            if status == "success":
                return response, True
            if status in TERMINAL_FAILURES:
                raise RuntimeError(f"MiniMax task {task_id} ended with status {status}: {response}")
        else:
            task = response.get("task") or {}
            status = str(task.get("status", "")).strip().lower()
            if status == "succeeded":
                return task, False
            if status in TERMINAL_FAILURES:
                raise RuntimeError(f"MiniMax task {task_id} ended with status {status}: {task}")

        if status != last_status:
            print(f"Task {task_id}: {status or 'unknown'}", file=sys.stderr)
            last_status = status
        time.sleep(poll_interval)
    raise TimeoutError(f"Timed out after {timeout_seconds} seconds waiting for MiniMax task {task_id}")


def submit_task(base_url: str, api_key: str, route: str, payload: dict[str, Any]) -> str:
    response = request_json("POST", f"{base_url}{route}", api_key, payload)
    task_id = response.get("task_id")
    if not task_id:
        raise RuntimeError(f"MiniMax create response did not include task_id: {response}")
    return str(task_id)


def resolve_download_url(
    base_url: str,
    api_key: str,
    task_result: dict[str, Any],
    legacy: bool,
) -> str:
    if not legacy:
        url = (task_result.get("content") or {}).get("url")
        if url:
            return str(url)
        raise RuntimeError(f"Succeeded task did not include task.content.url: {task_result}")

    file_id = task_result.get("file_id")
    if not file_id:
        raise RuntimeError(f"Legacy succeeded task did not include file_id: {task_result}")
    query = urllib.parse.urlencode({"file_id": file_id})
    response = request_json("GET", f"{base_url}/v1/files/retrieve?{query}", api_key)
    url = (response.get("file") or {}).get("download_url")
    if not url:
        raise RuntimeError(f"MiniMax file response did not include download_url: {response}")
    return str(url)


def download_file(url: str, output: Path, overwrite: bool) -> None:
    if output.exists() and not overwrite:
        raise FileExistsError(f"Output already exists: {output}. Pass --overwrite to replace it.")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "minimax-h3-pet-live-wallpaper/1.0"})
        with urllib.request.urlopen(request, timeout=300) as response, temporary.open("wb") as handle:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)
        if temporary.stat().st_size == 0:
            raise RuntimeError("Downloaded video is empty")
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", default="01", help="Scene ID 01-15 or scene slug (default: 01)")
    parser.add_argument("--pet", help="Local pet image mapped to <Picture 1> in Ref2VA mode")
    parser.add_argument(
        "--background",
        help="Override the bundled background mapped to <Picture 2> in Ref2VA mode",
    )
    parser.add_argument("--output", help="Output MP4 path")
    parser.add_argument("--resolution", choices=["768P", "2K"], default="2K")
    parser.add_argument("--duration", type=int, default=8, help="Integer seconds from 4 to 15")
    parser.add_argument(
        "--ratio",
        choices=["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
        default="16:9",
        help="Ref2VA output ratio (default: 16:9)",
    )
    parser.add_argument("--context-ir", action="store_true", help="Run paid Context-IR enhancement first")
    parser.add_argument("--prompt-extra", help="Append a small user-supplied prompt adjustment")
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs and print request summary without API calls")
    parser.add_argument("--list-scenes", action="store_true", help="List the fifteen bundled scenes and exit")
    parser.add_argument("--poll-interval", type=float, default=10.0)
    parser.add_argument("--timeout", type=int, default=3600, help="Task timeout in seconds")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("MINIMAX_API_BASE_URL", DEFAULT_BASE_URL),
        help="MiniMax-compatible base URL",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 4 <= args.duration <= 15:
        raise ValueError("--duration must be an integer from 4 to 15")
    if args.poll_interval < 1:
        raise ValueError("--poll-interval must be at least 1 second")
    if args.timeout < 30:
        raise ValueError("--timeout must be at least 30 seconds")

    presets = load_presets()
    if args.list_scenes:
        for scene in presets["scenes"]:
            print(f"{scene['id']}  {scene['title_zh']}  ({scene['slug']})")
        return 0

    scene = get_scene(presets, args.scene)
    payload, summary = build_payload(presets, scene, args)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.dry_run:
        return 0
    if not args.output:
        raise ValueError("--output is required unless --dry-run is used")

    api_key = os.environ.get("MINIMAX_API_KEY")
    if not api_key:
        raise RuntimeError(
            "MINIMAX_API_KEY is not set. Set it locally in your environment; do not paste it into chat or project files."
        )
    base_url = args.base_url.rstrip("/")

    if args.context_ir:
        context_payload = {
            "model": payload["model"],
            "content": payload["content"],
            "duration": payload["duration"],
            "ratio": payload["ratio"],
        }
        context_task_id = submit_task(base_url, api_key, "/v2/h3_context_ir", context_payload)
        print(f"Context-IR task: {context_task_id}", file=sys.stderr)
        context_result, legacy = poll_task(
            base_url, api_key, context_task_id, args.poll_interval, args.timeout
        )
        if legacy:
            raise RuntimeError("Context-IR completed through a legacy gateway that did not expose content.prompt")
        enhanced_prompt = (context_result.get("content") or {}).get("prompt")
        if not enhanced_prompt:
            raise RuntimeError(f"Context-IR task did not include content.prompt: {context_result}")
        payload["content"][0]["text"] = enhanced_prompt
        print("Context-IR prompt enhancement completed.", file=sys.stderr)

    task_id = submit_task(base_url, api_key, "/v2/video_generation", payload)
    print(f"Video task: {task_id}", file=sys.stderr)
    task_result, legacy = poll_task(base_url, api_key, task_id, args.poll_interval, args.timeout)
    download_url = resolve_download_url(base_url, api_key, task_result, legacy)
    output = Path(args.output).expanduser().resolve()
    download_file(download_url, output, args.overwrite)
    print(f"Saved: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, TimeoutError, FileExistsError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(2)
