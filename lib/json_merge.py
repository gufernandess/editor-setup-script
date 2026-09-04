#!/usr/bin/env python3
"""Shallow-merge a JSON overlay value into a target JSON file.

Usage:
    json_merge.py <target_path> <overlay_source_path> [--overlay-key KEY]

If --overlay-key is given, the overlay value is
json.load(overlay_source_path)[KEY]; otherwise it's the whole content
of overlay_source_path. If target_path is missing or empty, the
overlay is written as-is. Objects merge shallowly (overlay wins per
key, target-only keys survive). Arrays merge as a deduped union
(target items first, then overlay items not already present). Any
other type combination is an error.
"""
import argparse
import json
import sys


def shallow_merge(target, overlay):
    if isinstance(target, dict) and isinstance(overlay, dict):
        merged = dict(target)
        merged.update(overlay)
        return merged
    if isinstance(target, list) and isinstance(overlay, list):
        merged = list(target)
        for item in overlay:
            if item not in merged:
                merged.append(item)
        return merged
    raise TypeError(
        f"cannot merge {type(target).__name__} target with "
        f"{type(overlay).__name__} overlay"
    )


def load_json_or_none(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except FileNotFoundError:
        return None
    return json.loads(content) if content else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target_path")
    parser.add_argument("overlay_source_path")
    parser.add_argument("--overlay-key", default=None)
    args = parser.parse_args()

    with open(args.overlay_source_path, "r", encoding="utf-8") as f:
        overlay_source = json.load(f)

    if args.overlay_key is not None:
        if args.overlay_key not in overlay_source:
            print(
                f"error: key '{args.overlay_key}' not found in "
                f"{args.overlay_source_path}",
                file=sys.stderr,
            )
            return 1
        overlay = overlay_source[args.overlay_key]
    else:
        overlay = overlay_source

    try:
        target = load_json_or_none(args.target_path)
    except json.JSONDecodeError:
        print(
            f"error: {args.target_path} is not valid JSON",
            file=sys.stderr,
        )
        return 1

    if target is None:
        result = overlay
    else:
        try:
            result = shallow_merge(target, overlay)
        except TypeError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    with open(args.target_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
