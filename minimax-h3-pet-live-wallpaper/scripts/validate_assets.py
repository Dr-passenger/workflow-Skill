#!/usr/bin/env python3
"""Validate the fifteen bundled background images and their scene mappings."""

from __future__ import annotations

import json
import re
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
            "safe_zone_en",
            "loop_pose_en",
            "surface_response_en",
            "ambient_cycle_en",
            "state_restore_en",
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
    if (presets.get("defaults") or {}).get("duration") != 8:
        errors.append("default duration must be fixed to 8 seconds")

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
    for placeholder in (
        "{duration}",
        "{setting_notes}",
        "{safe_zone}",
        "{loop_pose}",
        "{surface_response}",
        "{ambient_cycle}",
        "{state_restore}",
        "{action}",
        "{extra_direction}",
    ):
        if placeholder not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing placeholder {placeholder}")
    for label in ("<Picture 1>", "<Picture 2>", "<Subject 1>", "<Subject 2>"):
        if label not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing reference label {label}")
    for marker in ("[reference generation]", "fully_preserved", "[Shot 1]"):
        if marker not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing Ref2VA marker {marker}")

    loop_markers = (
        "0.00 seconds",
        "8.00 seconds",
        "final frame must match",
        "solid collision boundary",
        "visible air gap",
    )
    for marker in loop_markers:
        if marker not in all_template_text:
            errors.append(f"ref2va_prompt_template_en: missing loop/collision marker {marker}")

    if templates and section_order == expected_sections:
        for scene in scenes:
            scene_id = scene.get("id", "??")
            values = {
                "duration": 8,
                "setting_notes": scene.get("setting_notes_en", ""),
                "safe_zone": scene.get("safe_zone_en", ""),
                "loop_pose": scene.get("loop_pose_en", ""),
                "surface_response": scene.get("surface_response_en", ""),
                "ambient_cycle": scene.get("ambient_cycle_en", ""),
                "state_restore": scene.get("state_restore_en", ""),
                "action": scene.get("action_en", ""),
                "extra_direction": "",
            }
            try:
                rendered_sections = {
                    section: str(templates[section]).format(**values).strip()
                    for section in expected_sections
                }
            except (KeyError, ValueError) as exc:
                errors.append(f"scene {scene_id}: cannot render Ref2VA prompt: {exc}")
                continue
            detailed = rendered_sections["detailed_description"]
            word_count = len(re.findall(r"\b[\w'-]+\b", detailed))
            if not 350 <= word_count <= 500:
                errors.append(
                    f"scene {scene_id}: detailed_description has {word_count} words; expected 350-500"
                )
            prompt = "\n\n".join(
                f"{section}:\n{rendered_sections[section]}" for section in expected_sections
            )
            if len(prompt) > 7000:
                errors.append(f"scene {scene_id}: rendered prompt exceeds 7000 characters")
            for marker in loop_markers:
                if marker not in prompt:
                    errors.append(f"scene {scene_id}: rendered prompt missing {marker}")
            action = str(scene.get("action_en", "")).lower()
            if not any(
                term in action
                for term in (
                    "without touch",
                    "without contact",
                    "without entering",
                    "without sinking",
                    "never enters",
                    "never touches",
                    "visible gap",
                    "air gap",
                )
            ):
                errors.append(f"scene {scene_id}: action must explicitly prohibit prop contact")

            physics_text = " ".join(
                str(scene.get(key, "")).lower()
                for key in ("surface_response_en", "ambient_cycle_en", "state_restore_en")
            )
            for physics_marker in ("paw", "restore"):
                if physics_marker not in physics_text:
                    errors.append(
                        f"scene {scene_id}: physics details missing required marker {physics_marker}"
                    )
            if scene_id == "15":
                for snow_marker in ("print", "shallow", "reverse", "no extra"):
                    if snow_marker not in physics_text:
                        errors.append(
                            f"scene 15: snow interaction missing required marker {snow_marker}"
                        )

    if errors:
        print("\nValidation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("\nAll 15 backgrounds and scene presets are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
