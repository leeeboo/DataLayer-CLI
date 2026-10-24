#!/usr/bin/env python3
"""Export an identical moved project and inspect every decoded frame and saved setting."""
import argparse
import hashlib
import json
import pathlib
import platform
import subprocess


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_frames", "-of", "json", str(path)
    ], timeout=120))


def inspect(path, codec, expected):
    metadata = probe(path)
    video = next(s for s in metadata["streams"] if s["codec_type"] == "video")
    frames = [f for f in metadata["frames"] if f["media_type"] == "video"]
    assert video["codec_name"] == {"h264": "h264", "hevc": "hevc", "prores-4444": "prores"}[codec], video
    assert (video["width"], video["height"]) == (expected["width"], expected["height"]), video
    assert video["avg_frame_rate"] == expected["fps"], video
    assert len(frames) == expected["frame_count"], len(frames)
    assert abs(float(video["duration"]) - expected["video_duration"]) < .000002, video
    for index, frame in enumerate(frames):
        assert abs(float(frame["best_effort_timestamp_time"]) - index * 1001 / 30000) < .000002, frame
    audio = [s for s in metadata["streams"] if s["codec_type"] == "audio"]
    if codec == "prores-4444":
        assert not audio, audio
        assert video["pix_fmt"].startswith("yuva"), video
    else:
        assert audio and all(s["codec_name"] == "aac" and int(s["sample_rate"]) == 48000 and s["channels"] == 2 for s in audio), audio
        assert abs(max(float(s["duration"]) for s in audio) - expected["requested_duration"]) < 1 / 48000, audio
        # AVFoundation can preserve separate AAC tracks; compare their audible sum as well as retaining stream metadata.
        graph = "".join(f"[0:a:{i}]" for i in range(len(audio))) + f"amix=inputs={len(audio)}:normalize=0[mix]"
        pcm = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-filter_complex", graph,
            "-map", "[mix]", "-ar", "48000", "-ac", "2", "-f", "s16le", "pipe:1"], timeout=120)
        path.with_suffix(".pcm").write_bytes(pcm)
        assert len(pcm) // 4 >= expected["audio_samples_per_channel"], "Truncated audio"
    command = ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:v:0", "-f", "rawvideo", "-pix_fmt", "bgra", "pipe:1"]
    hashes, alpha_summary = [], []
    size = expected["width"] * expected["height"] * 4
    with subprocess.Popen(command, stdout=subprocess.PIPE) as decoder:
        while True:
            frame = decoder.stdout.read(size)
            if not frame:
                break
            assert len(frame) == size, "Incomplete decoded frame"
            hashes.append(hashlib.sha256(frame).hexdigest())
            alpha = frame[3::4]
            if codec == "prores-4444":
                corners = [alpha[i] for i in [0, expected["width"] - 1, len(alpha) - expected["width"], len(alpha) - 1]]
                assert corners == [0, 0, 0, 0], corners
                assert min(alpha) == 0 and max(alpha) > 200, "Missing visible overlay or transparency"
                partial = len(alpha) - alpha.count(0) - alpha.count(255)
                assert partial > 0, "Missing partially transparent pixels"
                alpha_summary.append({"sha256": hashlib.sha256(alpha).hexdigest(), "nonzero": len(alpha) - alpha.count(0), "partial": partial})
            else:
                assert alpha.count(255) == len(alpha), "Opaque export lost pixels"
        assert decoder.wait(timeout=30) == 0
    assert len(hashes) == expected["frame_count"], len(hashes)
    return {"video": video, "audio": audio, "decoded_audio_samples_per_channel": len(pcm) // 4 if audio else 0,
            "frame_sha256": hashes, "alpha": alpha_summary}


def verify(binary, fixture, output):
    fixture, output = pathlib.Path(fixture).resolve(), pathlib.Path(output).resolve()
    expected = json.loads((fixture / "fixture.json").read_text())
    project = fixture / "moved-project"
    assert expected["synthetic"] and expected["original_directory_removed"]
    assert not (fixture / "original").exists()
    for relative, digest in expected["files"].items():
        assert hashlib.sha256((project / relative).read_bytes()).hexdigest() == digest, relative
    output.mkdir(parents=True, exist_ok=False)
    report = {"platform": platform.platform(), "fixture": expected, "exports": {}}
    for codec in ["h264", "hevc", "prores-4444"]:
        target = output / (codec + ".mov")
        try:
            with (output / (codec + ".log")).open("wb") as log:
                subprocess.run([str(pathlib.Path(binary).resolve()), "--timeline-project", str(project / (codec + ".dlsproj")), "--output", str(target)], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            print((output / (codec + ".log")).read_text(encoding="utf-8", errors="replace")[-16384:], flush=True)
            raise
        text = (output / (codec + ".log")).read_text(encoding="utf-8")
        for inherited in ["960x540", "29.970 fps", "1.350...5.850 s", "4300 kbps", "Time zone: UTC"]:
            assert inherited in text, (codec, inherited, text)
        report["exports"][codec] = inspect(target, codec, expected)
    assert not list(output.glob(".DataLayerStudio-*")), "Export scratch was not cleaned"
    assert not list(output.glob("*_01.mov")), "Saved single-file scope was ignored"
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"platform": report["platform"], "exports": list(report["exports"]), "frames_each": expected["frame_count"], "real_alpha": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("fixture")
    parser.add_argument("output")
    args = parser.parse_args()
    verify(args.binary, args.fixture, args.output)
