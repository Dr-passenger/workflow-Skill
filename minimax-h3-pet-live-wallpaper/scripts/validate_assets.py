#!/usr/bin/env python3
"""Validate the fifteen bundled background images and their scene mappings."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
PRESETS_PATH = SKILL_DIR / "references" / "scene-presets.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG with an IHDR header")
    return struct.unpack(">II", header[16:24])


def main() -> int:
    with PRESETS_PATH.open("r", encoding="utf-8") as handle:
        presets = json.load(handle)

    errors: list[str] = []
    scenes = presets.get("scenes", [])
    if len(scenes) != 15:
        errors.append(f"expected 15 scenes, found {len(scenes)}")

    ids = [scene.get("id") for scene in scenes]
    expected_ids = [f"{index:02d}" for index in range(1, 16)]
    if ids != expected_ids:
        errors.append(f"scene IDs must be ordered {expected_ids}, found {ids}")

    seen_paths: set[str] = set()
    for scene in scenes:
        scene_id = scene.get("id", "??")
        for key in (
            "slug",
            "title_zh",
            "background",
            "action_zh",
            "setting_notes_en",
            "action_en",
            "background_generation_prompt_en",
        ):
            if not str(scene.get(key, "")).strip():
                errors.append(f"scene {scene_id}: missing {key}")

        background_value = str(scene.get("background", ""))
        if background_value in seen_paths:
            errors.append(f"scene {scene_id}: duplicate background mapping {background_value}")
        seen_paths.add(background_value)
        background = SKILL_DIR / background_value
        if not background.is_file():
            errors.append(f"scene {scene_id}: background does not exist: {background}")
            continue
        try:
            width, height = png_dimensions(background)
        except ValueError as exc:
            errors.append(f"scene {scene_id}: {background.name}: {exc}")
            continue
        ratio = width / height
        if not (256 <= width <= 5760 and 256 <= height <= 5760):
            errors.append(f"scene {scene_id}: dimensions {width}x{height} are outside H3 image limits")
        if abs(ratio - 16 / 9) > 0.02:
            errors.append(f"scene {scene_id}: expected about 16:9, found {width}x{height} ({ratio:.4f})")
        print(f"OK  {scene_id}  {background.name}  {width}x{height}")

    if presets.get("api_model") != "MiniMax-H3":
        errors.append("api_model must be MiniMax-H3")
    if presets.get("model_variant") != "H3-Base-Ref2VA":
        errors.append("model_variant must be H3-Base-Ref2VA")
    if presets.get("input_mode") != "ref2va":
        errors.append("input_mode must be ref2va")

    expected_sections = [
        "subject_definitions",
        "summary",
        "retention_analysis",
        "detailed_description",
        "overall_soundscape",
        "non_diegetic_music",
    ]
    section_order = presets.get("ref2va_section_order")
    if section_order != expected_sections:
        errors.append(f"Ref2VA section order must be {expected_sections}, found {section_order}")

    templates = presets.get("ref2va_prompt_template_en")
    if not isinstance(templates, dict):
        errors.append("ref2va_prompt_template_en must be an object")
        templates = {}
    for section in expected_sections:
        if not str(templates.get(section, "")).strip():
            errors.append(f"ref2va_prompt_template_en: missing {section}")

    all_template_text = "\n".join(str(templates.get(section, "")) for section in expected_sections)
    for placeholder in ("{duration}", "{setting_notes}", "{action}", "{extra_direction}"):
        if placeholder not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing placeholder {placeholder}")
    for label in ("<Picture 1>", "<Picture 2>", "<Subject 1>", "<Subject 2>"):
        if label not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing reference label {label}")
    for marker in ("[reference generation]", "fully_preserved", "[Shot 1]"):
        if marker not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing Ref2VA marker {marker}")

    if errors:
        print("\nValidation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("\nAll 15 backgrounds and scene presets are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
