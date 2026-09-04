import argparse
import json
import sys


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

    with open(args.target_path, "w", encoding="utf-8") as f:
        json.dump(overlay, f, indent=2, ensure_ascii=False)
        f.write("\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
