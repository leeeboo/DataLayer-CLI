#!/usr/bin/env python3
"""Gate portable visual parity and all-platform audio; report Apple rendering differences."""
import argparse
import array
import json
import math
import pathlib
import re
import subprocess
import tempfile


def similarity(left, right, alpha=False):
    with tempfile.TemporaryDirectory(prefix="datalayer-parity-") as directory:
        graph = "[0:v]alphaextract[a];[1:v]alphaextract[b];[a][b]" if alpha else ""
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(left), "-i", str(right), "-lavfi",
            graph + "ssim=stats_file=frames.txt", "-an", "-f", "null", "-"], cwd=directory, check=True, timeout=120)
        scores = [float(re.search(r"All:([.\d]+)", line)[1]) for line in (pathlib.Path(directory) / "frames.txt").read_text().splitlines()]
        assert len(scores) == 135, len(scores)
        return {"mean": sum(scores) / len(scores), "minimum": min(scores), "per_frame": scores}


def audio(left, right):
    a, b = array.array("h", left.read_bytes()), array.array("h", right.read_bytes())
    # Stream durations are checked separately; retain the decoder's AAC padding in the report.
    count = 216000 * 2
    assert min(len(a), len(b)) >= count
    a, b = a[:count], b[:count]
    aa, bb = sum(x * x for x in a), sum(y * y for y in b)
    correlation = sum(x * y for x, y in zip(a, b)) / math.sqrt(aa * bb)
    rms_delta = math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)) / count) / 32768
    return {"correlation": correlation, "rms_delta": rms_delta, "samples_per_channel": count // 2}


def compare(root, output):
    root, output = pathlib.Path(root).resolve(), pathlib.Path(output).resolve()
    reports = {name: json.loads((root / ("export-" + name) / "report.json").read_text()) for name in ["macos", "linux", "windows"]}
    assert all(r["fixture"] == reports["macos"]["fixture"] for r in reports.values()), "Platforms used different input media or projects"
    comparisons, failures, visual_differences = {}, [], []
    for left, right in [("macos", "linux"), ("macos", "windows"), ("linux", "windows")]:
        pair = left + "-" + right
        require_visual_parity = (left, right) == ("linux", "windows")
        comparisons[pair] = {}
        for codec in ["h264", "hevc", "prores-4444"]:
            a, b = root / ("export-" + left) / codec, root / ("export-" + right) / codec
            picture = similarity(a.with_suffix(".mov"), b.with_suffix(".mov"))
            result = {"picture": picture, "visual_parity_required": require_visual_parity}
            if picture["mean"] < .995 or picture["minimum"] < .99:
                difference = pair + "/" + codec + ": picture differs"
                visual_differences.append(difference)
                if require_visual_parity:
                    failures.append(difference)
            if codec == "prores-4444":
                result["alpha"] = similarity(a.with_suffix(".mov"), b.with_suffix(".mov"), alpha=True)
                if result["alpha"]["mean"] < .995 or result["alpha"]["minimum"] < .99:
                    difference = pair + "/" + codec + ": Alpha differs"
                    visual_differences.append(difference)
                    if require_visual_parity:
                        failures.append(difference)
            else:
                result["audio"] = audio(a.with_suffix(".pcm"), b.with_suffix(".pcm"))
                if result["audio"]["correlation"] < .995 or result["audio"]["rms_delta"] > .01:
                    failures.append(pair + "/" + codec + ": audio differs")
            comparisons[pair][codec] = result
    output.write_text(json.dumps({"passed": not failures, "failures": failures,
        "visual_differences": visual_differences, "comparisons": comparisons}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": not failures, "failures": failures, "visual_differences": visual_differences}))
    return not failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("exports")
    parser.add_argument("report")
    args = parser.parse_args()
    raise SystemExit(0 if compare(args.exports, args.report) else 1)
