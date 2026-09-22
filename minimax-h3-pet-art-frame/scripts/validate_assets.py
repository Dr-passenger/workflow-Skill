#!/usr/bin/env python3
"""Validate presets, background images, and generated prompt invariants."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path
from typing import Any


SKILL_ROOT = Path(__file__).resolve().parents[1]
PRESETS_PATH = SKILL_ROOT / "references" / "frame-presets.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        signature = handle.read(8)
        require(signature == b"\x89PNG\r\n\x1a\n", f"Not a PNG file: {path}")
        length = struct.unpack(">I", handle.read(4))[0]
        chunk_type = handle.read(4)
        require(length == 13 and chunk_type == b"IHDR", f"Malformed PNG header: {path}")
        width, height = struct.unpack(">II", handle.read(8))
    return width, height


def load_generator_module() -> Any:
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(SKILL_ROOT / "scripts"))
    import minimax_h3_art_frame  # type: ignore

    return minimax_h3_art_frame


def validate() -> None:
    presets = json.loads(PRESETS_PATH.read_text(encoding="utf-8"))
    require(presets["schema_version"] == 1, "schema_version must be 1")
    require(presets["model"] == "MiniMax-H3", "model must be MiniMax-H3")
    require(presets["duration"] == 8, "duration must be exactly 8 seconds")
    require(presets["resolution"] in {"768P", "2K"}, "unsupported resolution")
    require(presets["max_pets"] == 3, "max_pets must be 3")
    require(
        presets["modes"] == ["expression-loop", "left-inertia", "right-inertia"],
        "unexpected modes or mode order",
    )
    require(set(presets["composition_layouts_en"]) == {"1", "2", "3"}, "need layouts 1–3")

    frames = presets["frames"]
    require(len(frames) == 5, "exactly five frame presets are required")
    require([frame["id"] for frame in frames] == ["01", "02", "03", "04", "05"], "IDs must be 01–05")
    require(len({frame["slug"] for frame in frames}) == 5, "frame slugs must be unique")
    require(len({frame["background"] for frame in frames}) == 5, "background paths must be unique")

    required_fields = {
        "id",
        "slug",
        "title_zh",
        "background",
        "scene_style_en",
        "wardrobe_zh",
        "wardrobe_en",
    }
    for frame in frames:
        require(required_fields <= set(frame), f"missing fields in frame {frame.get('id')}")
        path = SKILL_ROOT / frame["background"]
        require(path.is_file(), f"missing background: {path}")
        width, height = png_dimensions(path)
        require(256 <= width <= 5760 and 256 <= height <= 5760, f"invalid dimensions: {path}")
        require(abs(width / height - 16 / 9) < 0.02, f"background is not near 16:9: {path}")

    realistic = frames[-1]
    require(realistic["slug"] == "realistic-white-black-edge", "preset 05 must be realistic white mode")
    realistic_rule = realistic["wardrobe_en"].lower()
    require("add nothing" in realistic_rule, "realistic mode must not add wardrobe")
    require("no stylization" in realistic_rule, "realistic mode must forbid stylization")

    static_rule = presets["global_static_constraints_en"].lower()
    require("every background pixel" in static_rule, "static rule must lock background pixels")
    require("no camera pan" in static_rule, "static rule must forbid camera motion")

    left = presets["inertia_timelines_en"]["left-inertia"].lower()
    right = presets["inertia_timelines_en"]["right-inertia"].lower()
    require("turning left" in left and "screen-right" in left and "screen-left" in left, "left-turn direction rule is incomplete")
    require("turning right" in right and "screen-left" in right and "screen-right" in right, "right-turn direction rule is incomplete")

    template = presets["composite_prompt_template_en"]
    for placeholder in ("{pet_count}", "{layout}", "{wardrobe}"):
        require(placeholder in template, f"composite prompt is missing {placeholder}")

    generator = load_generator_module()
    section_order = [
        "subject_definitions:",
        "summary:",
        "retention_analysis:",
        "detailed_description:",
        "overall_soundscape:",
        "non_diegetic_music:",
    ]
    for pet_count in (1, 2, 3):
        for frame in frames:
            composite = generator.build_composite_prompt(presets, frame, pet_count)
            require(len(composite) < 4000, "composite prompt is unexpectedly long")
            expression = generator.build_expression_prompt(presets, frame, pet_count)
            positions = [expression.index(section) for section in section_order]
            require(positions == sorted(positions), "Ref2VA sections are out of order")
            require(f"<Picture {pet_count + 1}>" in expression, "keyframe reference is missing")
            require("exactly 8.00 seconds" in expression, "expression endpoint is not explicit")
            require(len(expression) < 7000, "Ref2VA prompt is unexpectedly long")

            for mode in ("left-inertia", "right-inertia"):
                inertia = generator.build_inertia_prompt(presets, frame, pet_count, mode)
                require(inertia.startswith("How the reference pictures align"), "FL2VA alignment must be first")
                require("0.00-second mark" in inertia and "8.00-second mark" in inertia, "FL2VA endpoints missing")
                require("integrated_multimodal_description:" in inertia, "FL2VA core section missing")
                require("Picture 2 is an endpoint constraint" in inertia, "crossfade protection missing")
                require(len(inertia) < 7000, "FL2VA prompt is unexpectedly long")

    dummy_pets = [SKILL_ROOT / frame["background"] for frame in frames[:3]]
    dummy_keyframe = SKILL_ROOT / frames[-1]["background"]
    dummy_output = SKILL_ROOT / "output" / "dummy.mp4"
    expression_job = generator.build_job_manifest(
        presets,
        frames[0],
        dummy_pets,
        dummy_keyframe,
        "expression-loop",
        "2K",
        dummy_output,
    )
    expression_roles = [item["role"] for item in expression_job["inputs"]]
    require(expression_roles == ["reference_image"] * 4, "Ref2VA role plan is invalid")
    require(expression_job["pipeline"] == "Ref2VA", "expression mode must use Ref2VA")
    require(expression_job["ratio"] == "16:9", "Ref2VA ratio must be 16:9")
    require(expression_job["transport"]["official_minimax_api"] is False, "official API must be disabled")
    require(expression_job["runtime"] == "user-managed-remote-deployment", "wrong runtime")

    inertia_job = generator.build_job_manifest(
        presets,
        frames[0],
        dummy_pets,
        dummy_keyframe,
        "left-inertia",
        "2K",
        dummy_output,
    )
    inertia_roles = [item["role"] for item in inertia_job["inputs"]]
    require(inertia_roles == ["first_frame", "last_frame"], "FL2VA role plan is invalid")
    require(inertia_job["pipeline"] == "FL2VA", "inertia mode must use FL2VA")
    require(inertia_job["ratio"] == "adaptive", "FL2VA ratio must be adaptive")

    runtime_script = (SKILL_ROOT / "scripts" / "minimax_h3_art_frame.py").read_text(encoding="utf-8")
    require("api.minimax.io" not in runtime_script, "official MiniMax host found in runtime script")
    require("MINIMAX_API_KEY" not in runtime_script, "official API key found in runtime script")
    require("urllib.request" not in runtime_script, "runtime script must not contain a built-in HTTP client")

    print(
        f"OK: validated {len(frames)} frame presets, {len(frames)} PNG assets, "
        "1–3 pet prompts, and private remote job manifests."
    )


if __name__ == "__main__":
    try:
        validate()
    except (AssertionError, KeyError, ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
