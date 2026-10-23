#!/usr/bin/env python3
"""Write five seconds of synthetic telemetry to a new GPX file."""
import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: make_sample.py /path/to/new-sample.gpx")
points = "".join(
    f'<trkpt lat="{i * .00002:.5f}" lon="0"><ele>{20 + i}</ele>'
    f'<time>2026-01-01T00:00:0{i}Z</time></trkpt>'
    for i in range(6)
)
with pathlib.Path(sys.argv[1]).open("x") as sample:
    sample.write('<gpx version="1.1" creator="DataLayer-CLI" '
                 'xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>'
                 + points + '</trkseg></trk></gpx>\n')
