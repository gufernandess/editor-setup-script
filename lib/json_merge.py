#!/usr/bin/env python3
"""Shallow-merge a JSON overlay value into a target JSON file.

Usage:
    json_merge.py <target_path> <overlay_source_path> [--overlay-key KEY]
                  [--nested-merge-key DOTTED_PATH ...]

If --overlay-key is given, the overlay value is
json.load(overlay_source_path)[KEY]; otherwise it's the whole content
of overlay_source_path. If target_path is missing or empty, the
overlay is written as-is. Objects merge shallowly (overlay wins per
key, target-only keys survive). Arrays merge as a deduped union
(target items first, then overlay items not already present). Any
other type combination is an error.

--nested-merge-key may be given one or more times with a dotted path
(e.g. "mcpServers" or "powers.mcpServers"). For each such path, instead
of the overlay's dict at that path replacing the target's dict wholesale
(the normal shallow-merge behavior), the two dicts found at that path
are merged one level deeper: overlay wins per key within that dict,
and target-only keys survive. This is how mcp.json's mcpServers (and
powers.mcpServers) need to behave, so a user's existing MCP servers
that aren't in the overlay are not silently dropped.

An existing target file may contain JSONC (// line comments, /* */
block comments, and trailing commas before } or ]), matching what VS
Code / Kiro-family editors accept in settings.json and keybindings.json.
"""
import argparse
import json
import re
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


def _get_nested(d, parts):
    cur = d
    for p in parts:
        if not isinstance(cur, dict) or p not in cur:
            return None
        cur = cur[p]
    return cur


def _set_nested(d, parts, value):
    cur = d
    for p in parts[:-1]:
        nxt = cur.get(p)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[p] = nxt
        cur = nxt
    cur[parts[-1]] = value


def merge_with_nested_keys(target, overlay, nested_keys):
    """Shallow-merge target/overlay, but for each dotted path in
    nested_keys, merge the dicts found at that path one level deeper
    (overlay wins per key within that dict) instead of letting the
    overlay's dict at that path replace the target's wholesale.
    """
    merged = shallow_merge(target, overlay)
    for dotted in nested_keys:
        parts = dotted.split(".")
        t_val = _get_nested(target, parts)
        o_val = _get_nested(overlay, parts)
        if isinstance(t_val, dict) and isinstance(o_val, dict):
            _set_nested(merged, parts, shallow_merge(t_val, o_val))
    return merged


def strip_jsonc(text):
    """Best-effort strip of JSONC-only syntax (// and /* */ comments,
    trailing commas before } or ]) so the result can be parsed with
    json.loads. Tracks whether we're inside a string literal so comment
    markers inside string values are left untouched.
    """
    result = []
    i = 0
    n = len(text)
    in_string = False
    escape = False
    while i < n:
        c = text[i]
        if in_string:
            result.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            result.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] not in ("\n", "\r"):
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        result.append(c)
        i += 1
    stripped = "".join(result)
    # Trailing commas before a closing } or ]
    stripped = re.sub(r",(\s*[}\]])", r"\1", stripped)
    return stripped


def load_json_or_none(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except FileNotFoundError:
        return None
    if not content:
        return None
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return json.loads(strip_jsonc(content))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target_path")
    parser.add_argument("overlay_source_path")
    parser.add_argument("--overlay-key", default=None)
    parser.add_argument(
        "--nested-merge-key",
        action="append",
        default=[],
        metavar="DOTTED_PATH",
        help=(
            "dotted path (may repeat) whose dict value should be merged "
            "one level deeper instead of replaced wholesale"
        ),
    )
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
            if args.nested_merge_key:
                result = merge_with_nested_keys(target, overlay, args.nested_merge_key)
            else:
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
