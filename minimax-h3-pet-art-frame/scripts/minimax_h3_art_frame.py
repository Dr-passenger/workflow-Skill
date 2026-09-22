#!/usr/bin/env python3
"""Build transport-neutral jobs for a remotely deployed MiniMax-H3 model.

This script never calls MiniMax's official public API. It exports Ref2VA/FL2VA
job manifests and can optionally pass each manifest to a user-supplied runner.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


SKILL_ROOT = Path(__file__).resolve().parents[1]
PRESETS_PATH = SKILL_ROOT / "references" / "frame-presets.json"
SUPPORTED_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
MAX_IMAGE_BYTES = 30 * 1024 * 1024


def load_presets() -> dict[str, Any]:
    with PRESETS_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_frame(presets: dict[str, Any], selector: str) -> dict[str, Any]:
    for frame in presets["frames"]:
        if selector in {frame["id"], frame["slug"]}:
            return frame
    choices = ", ".join(f"{item['id']} ({item['slug']})" for item in presets["frames"])
    raise ValueError(f"Unknown frame '{selector}'. Choose one of: {choices}")


def validate_image(path_text: str, label: str) -> Path:
    path = Path(path_text).expanduser().resolve()
    if not path.is_file():
        raise ValueError(f"{label} does not exist or is not a file: {path}")
    if path.suffix.lower() not in SUPPORTED_SUFFIXES:
        raise ValueError(f"{label} must be JPG, JPEG, PNG, WEBP, HEIC, or HEIF: {path}")
    if path.stat().st_size > MAX_IMAGE_BYTES:
        raise ValueError(f"{label} exceeds the workflow's 30 MB image limit: {path}")
    return path


def build_composite_prompt(
    presets: dict[str, Any], frame: dict[str, Any], pet_count: int
) -> str:
    return presets["composite_prompt_template_en"].format(
        pet_count=pet_count,
        layout=presets["composition_layouts_en"][str(pet_count)],
        wardrobe=frame["wardrobe_en"],
    )


def _pet_subject_definitions(pet_count: int) -> list[str]:
    definitions = []
    for index in range(1, pet_count + 1):
        definitions.append(
            f"- <Subject {index}>: the distinct real household pet shown in <Picture {index}>. "
            "Preserve that pet's species and breed traits, facial geometry, eyes, ears, coat "
            "colors, exact marking boundaries, body proportions, age impression, tail, and "
            "existing accessories; never transfer traits between pets."
        )
    definitions.append(
        f"- <Subject {pet_count + 1}>: the finished pet art-frame composition shown in "
        f"<Picture {pet_count + 1}>, including the exact pet arrangement, wardrobe, border, "
        "background, camera, lighting, shadows, and crop."
    )
    return definitions


def build_expression_prompt(
    presets: dict[str, Any], frame: dict[str, Any], pet_count: int
) -> str:
    keyframe_picture = pet_count + 1
    subjects = "\n".join(_pet_subject_definitions(pet_count))
    return f"""subject_definitions:
{subjects}

summary:
Create one continuous 8-second photorealistic expression loop from <Picture {keyframe_picture}>. The finished {frame['title_zh']} art frame stays perfectly fixed. All {pet_count} pet(s) remain almost motionless in the exact opening positions while showing rich, natural, species-appropriate facial expressions. The first and last frames must visually match.

retention_analysis:
Retain each <Subject 1> through <Subject {pet_count}> from its own identity picture and use <Picture {keyframe_picture}> as the authoritative layout and style reference. Preserve exact identities, coat patterns, anatomy, relative scale, spacing, wardrobe, contact shadows, border, and full {frame['scene_style_en']}. Do not add, remove, merge, duplicate, recolor, or restyle any pet. {presets['global_static_constraints_en']}

detailed_description:
One fixed full-frame 16:9 shot for the entire 8.00 seconds. Body pose, paws, legs, haunches, torso, tail base, and contact points stay locked to <Picture {keyframe_picture}>; only eyelids, gaze, anatomically plausible brow area, ear angle by a few degrees, nose, whiskers, and mouth corners may move. No head translation, body sway, walking, paw lift, lip-sync, tongue extrusion, human smile, talking, or exaggerated cartoon acting. Keep the pets separate and offset their micro-expressions naturally. {presets['expression_timeline_en']} At exactly 8.00 seconds restore every allowed moving feature, gaze direction, eyelid state, ear angle, whisker position, and mouth shape to the 0.00-second state so the loop boundary is clean. Never move or animate the background, frame, scene effects, lighting, shadows unrelated to pets, or camera.

overall_soundscape:
Silent video. No voice, bark, meow, panting, room ambience, vehicle sound, or sound effect.

non_diegetic_music:
N/A"""


def build_inertia_prompt(
    presets: dict[str, Any], frame: dict[str, Any], pet_count: int, mode: str
) -> str:
    direction = "left" if mode == "left-inertia" else "right"
    timeline = presets["inertia_timelines_en"][mode]
    return f"""How the reference pictures align with the target video — Picture 1 (from Shot 1) aligns with the 0.00-second mark of the target video; Picture 2 (from Shot 1) aligns with the 8.00-second mark of the target video.

integrated_multimodal_description:
Create one uninterrupted 8-second photorealistic simulation of a gentle vehicle turn to the {direction}, using <Picture 1> as the exact opening frame and the identical <Picture 2> as the exact ending frame. There are exactly {pet_count} distinct pet(s) in the finished {frame['title_zh']} art-frame composition. Preserve every pet's identity, species, face, eyes, ears, coat colors and exact marking boundaries, anatomy, body proportions, relative scale, spacing, wardrobe, and contact points from both pictures. Preserve the exact {frame['scene_style_en']}. {presets['global_static_constraints_en']} Only the pets' soft tissues and safely fitted low-profile accessories respond to inertia; no pet walks, jumps, slides, changes seat, lifts a planted paw, collides, overlaps, stretches, deforms, gains or loses a limb, or intersects the frame. Give each pet a subtly different response amplitude according to apparent size while keeping the group coherent. {timeline} Picture 2 is an endpoint constraint, not a crossfade: do not dissolve, morph, cut, fade, or freeze abruptly. At exactly 8.00 seconds all pet pixels, poses, expressions, fur tips, accessories, shadows, and contact points must have naturally settled back onto Picture 2.

overall_soundscape:
Silent video. No engine, road noise, voice, bark, meow, ambience, or sound effect.

non_diegetic_music:
N/A"""


def make_input(picture: int, role: str, path: Path) -> dict[str, Any]:
    return {
        "picture": picture,
        "role": role,
        "path": str(path),
    }


def build_job_manifest(
    presets: dict[str, Any],
    frame: dict[str, Any],
    pet_paths: list[Path],
    keyframe: Path,
    mode: str,
    resolution: str,
    output_path: Path,
) -> dict[str, Any]:
    if mode == "expression-loop":
        prompt = build_expression_prompt(presets, frame, len(pet_paths))
        inputs = [
            make_input(index, "reference_image", path)
            for index, path in enumerate(pet_paths, start=1)
        ]
        inputs.append(make_input(len(inputs) + 1, "reference_image", keyframe))
        pipeline = "Ref2VA"
        ratio = "16:9"
    else:
        prompt = build_inertia_prompt(presets, frame, len(pet_paths), mode)
        inputs = [
            make_input(1, "first_frame", keyframe),
            make_input(2, "last_frame", keyframe),
        ]
        pipeline = "FL2VA"
        ratio = "adaptive"

    return {
        "schema_version": 1,
        "runtime": "user-managed-remote-deployment",
        "model": presets["model"],
        "pipeline": pipeline,
        "mode": mode,
        "frame": {"id": frame["id"], "slug": frame["slug"], "title_zh": frame["title_zh"]},
        "pet_count": len(pet_paths),
        "duration_seconds": presets["duration"],
        "resolution": resolution,
        "ratio": ratio,
        "prompt": prompt,
        "inputs": inputs,
        "output_path": str(output_path),
        "transport": {
            "kind": "external_runner",
            "official_minimax_api": False,
            "note": "The deployment runner must translate this manifest to the private remote runtime.",
        },
    }


def output_path_for_mode(args: argparse.Namespace, frame: dict[str, Any], mode: str) -> Path:
    if args.mode != "all" and args.output:
        return Path(args.output).expanduser().resolve()
    directory = Path(args.output_dir).expanduser().resolve()
    return directory / f"{frame['slug']}-{mode}.mp4"


def manifest_path_for_mode(export_dir: Path, frame: dict[str, Any], mode: str) -> Path:
    return export_dir / f"{frame['slug']}-{mode}.job.json"


def write_manifest(path: Path, manifest: dict[str, Any], overwrite: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not overwrite:
        raise ValueError(f"Job manifest already exists; pass --overwrite-jobs to replace it: {path}")
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_external_runner(
    executable: str,
    argument_templates: list[str],
    manifest_path: Path,
    manifest: dict[str, Any],
    timeout: int,
) -> None:
    substitutions = {
        "manifest": str(manifest_path),
        "output": manifest["output_path"],
        "mode": manifest["mode"],
        "pipeline": manifest["pipeline"],
    }
    rendered_args = [argument.format_map(substitutions) for argument in argument_templates]
    if not any("{manifest}" in argument for argument in argument_templates):
        rendered_args.append(str(manifest_path))
    command = [executable, *rendered_args]
    print(f"Running remote deployment adapter for {manifest['mode']}: {executable}", flush=True)
    subprocess.run(command, check=True, timeout=timeout, shell=False)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build MiniMax-H3 Ref2VA/FL2VA jobs for a user-managed remote deployment."
    )
    parser.add_argument("--list-frames", action="store_true", help="List the five included frames")
    parser.add_argument("--frame", default="01", help="Frame ID or slug (default: 01)")
    parser.add_argument(
        "--pet", action="append", default=[], metavar="IMAGE", help="Pet identity photo; repeat 1–3 times"
    )
    parser.add_argument("--keyframe", help="Finished composite keyframe containing all pets")
    parser.add_argument(
        "--print-composite-prompt",
        action="store_true",
        help="Print the image-compositing plan and exit",
    )
    parser.add_argument(
        "--mode",
        choices=("expression-loop", "left-inertia", "right-inertia", "all"),
        default="all",
    )
    parser.add_argument("--duration", type=int, default=8, help="Fixed at 8 seconds")
    parser.add_argument("--resolution", choices=("768P", "2K"), default="2K")
    parser.add_argument("--output", help="Expected MP4 path for a single mode")
    parser.add_argument("--output-dir", default="output", help="Expected video folder")
    parser.add_argument("--export-dir", default="output/jobs", help="Job manifest folder")
    parser.add_argument("--dry-run", action="store_true", help="Print jobs without writing or running")
    parser.add_argument("--overwrite-jobs", action="store_true")
    parser.add_argument(
        "--runner",
        help="Executable for the user's private remote-deployment adapter; omitted means export only",
    )
    parser.add_argument(
        "--runner-arg",
        action="append",
        default=[],
        help="Adapter argument; repeat as needed. Supports {manifest}, {output}, {mode}, {pipeline}",
    )
    parser.add_argument("--runner-timeout", type=int, default=7200)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    presets = load_presets()

    if args.list_frames:
        for frame in presets["frames"]:
            print(
                f"{frame['id']}  {frame['slug']}  {frame['title_zh']}\n"
                f"    背景: {SKILL_ROOT / frame['background']}\n"
                f"    装扮: {frame['wardrobe_zh']}"
            )
        return 0

    try:
        frame = resolve_frame(presets, args.frame)
        if args.duration != presets["duration"]:
            raise ValueError("This workflow is fixed at 8 seconds; use --duration 8.")
        if not 1 <= len(args.pet) <= presets["max_pets"]:
            raise ValueError("Provide 1–3 pet photos by repeating --pet.")
        pet_paths = [
            validate_image(path, f"Pet photo {index}")
            for index, path in enumerate(args.pet, start=1)
        ]

        if args.print_composite_prompt:
            background = (SKILL_ROOT / frame["background"]).resolve()
            plan = {
                "frame": frame["title_zh"],
                "input_order": [str(path) for path in pet_paths] + [str(background)],
                "input_roles": [f"pet identity {index}" for index in range(1, len(pet_paths) + 1)]
                + ["exact static background and frame"],
                "prompt": build_composite_prompt(presets, frame, len(pet_paths)),
            }
            print(json.dumps(plan, ensure_ascii=False, indent=2))
            return 0

        if not args.keyframe:
            raise ValueError("--keyframe is required for video jobs.")
        keyframe = validate_image(args.keyframe, "Composite keyframe")
        if args.mode != "all" and args.output_dir != "output" and args.output:
            raise ValueError("Use either --output or --output-dir, not both.")
        if args.runner_arg and not args.runner:
            raise ValueError("--runner-arg requires --runner.")

        modes = presets["modes"] if args.mode == "all" else [args.mode]
        export_dir = Path(args.export_dir).expanduser().resolve()
        jobs: list[tuple[Path, dict[str, Any]]] = []
        for mode in modes:
            output_path = output_path_for_mode(args, frame, mode)
            manifest = build_job_manifest(
                presets, frame, pet_paths, keyframe, mode, args.resolution, output_path
            )
            manifest_path = manifest_path_for_mode(export_dir, frame, mode)
            jobs.append((manifest_path, manifest))

        if args.dry_run:
            print(
                json.dumps(
                    [{"manifest_path": str(path), "job": job} for path, job in jobs],
                    ensure_ascii=False,
                    indent=2,
                )
            )
            return 0

        for manifest_path, manifest in jobs:
            write_manifest(manifest_path, manifest, args.overwrite_jobs)
            print(f"Saved job manifest: {manifest_path}", flush=True)
            if args.runner:
                run_external_runner(
                    args.runner,
                    args.runner_arg,
                    manifest_path,
                    manifest,
                    args.runner_timeout,
                )
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as exc:
        parser.error(str(exc))
        return 2


if __name__ == "__main__":
    sys.exit(main())
