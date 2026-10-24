#!/usr/bin/env python3
"""Generate the shared synthetic media once; every platform downloads the same artifact."""
import argparse
import copy
import hashlib
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def prepare(destination):
    destination = pathlib.Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    try:
        original = destination / "original"
        media = original / "Media"
        media.mkdir(parents=True)
        points = "".join(
            f'<trkpt lat="{i * .00002:.6f}" lon="{i * i * .000003:.6f}"><ele>{10+i}</ele>'
            f'<time>2026-01-01T00:00:0{i}Z</time></trkpt>' for i in range(9)
        )
        (media / "activity.gpx").write_text(
            '<gpx version="1.1" creator="DataLayer-CLI synthetic acceptance" '
            'xmlns="http://www.topografix.com/GPX/1/1"><trk><type>running</type><trkseg>'
            + points + '</trkseg></trk></gpx>\n', encoding="utf-8", newline="\n")
        for name, frequency, hue in [("scene-a", 440, 0), ("scene-b", 660, 75)]:
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                "-f", "lavfi", "-i", "testsrc2=size=960x540:rate=30000/1001:duration=7",
                "-f", "lavfi", "-i", f"sine=frequency={frequency}:sample_rate=48000:duration=7",
                "-vf", f"hue=h={hue},format=yuv420p", "-c:v", "libx264", "-preset", "fast", "-crf", "18",
                "-threads", "2", "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-color_range", "tv", "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "192k",
                "-video_track_timescale", "30000", "-movflags", "+faststart", "-f", "mov", str(media / (name + ".mov"))
            ], check=True, timeout=120)
        project = json.loads((ROOT / "Tests/Fixtures/ExportParity/project.json").read_text())
        assert project["outputWidth"] == 960 and project["outputHeight"] == 540
        assert project["exportSettings"]["timelineStart"] == 1.35 and project["exportSettings"]["timelineEnd"] == 5.85
        assert all(asset["url"].startswith("file:///DataLayer-CLI-missing-original-location/") and asset["relativePath"] for asset in project["assets"])
        for codec in ["h264", "hevc", "prores-4444"]:
            variant = copy.deepcopy(project)
            variant["exportSettings"].update(codec=codec, exportMode="overlay" if codec == "prores-4444" else "video")
            (original / (codec + ".dlsproj")).write_text(json.dumps(variant, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
        moved = destination / "moved-project"
        original.rename(moved)
        files = {str(p.relative_to(moved)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted(moved.rglob("*")) if p.is_file()}
        manifest = {"synthetic": True, "files": files, "original_directory_removed": not original.exists(),
                    "width": 960, "height": 540, "fps": "30000/1001", "frame_count": 135,
                    "video_duration": 4.5045, "requested_duration": 4.5, "audio_sample_rate": 48000,
                    "audio_samples_per_channel": 216000, "cached_weather": [[31, 57], [35, 68], [39, 79]]}
        (destination / "fixture.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"fixture": str(destination), "files": len(files), "moved": True}))
    except BaseException:
        shutil.rmtree(destination)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination")
    prepare(parser.parse_args().destination)
