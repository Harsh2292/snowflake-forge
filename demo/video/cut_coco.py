"""Trim the three CoCo CLI recordings: prompt at normal speed, the wait sped up, result at
normal speed. Output coco_1.mp4, coco_2.mp4, coco_3.mp4 (1920x1080, 30 fps, no audio).

python cut_coco.py "<Coco cli 1.mp4>" "<Coco cli 2.mp4>" "<Coco cli 3.mp4>"
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
# (start, end, speed) per piece; times read off the recordings of 4 Oct 2026
PLANS = [
    [(4.0, 8.5, 1), (8.5, 30.5, 5), (30.5, None, 1)],   # 1: data-quality; table appears at ~31 s
    [(2.2, 7.0, 1), (7.0, 39.5, 4), (39.5, None, 1)],   # 2: data-governance; Notepad visible before 2 s
    [(0.0, 4.0, 1), (4.0, 63.5, 6), (63.5, None, 1)],   # 3: agent; answer appears at ~64 s
]
FIT = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x1e1e1e,fps=30"

for i, (src, plan) in enumerate(zip(sys.argv[1:4], PLANS), 1):
    chains, labels = [], []
    for j, (a, b, speed) in enumerate(plan):
        end = f":end={b}" if b is not None else ""
        chains.append(f"[0:v]trim=start={a}{end},setpts=(PTS-STARTPTS)/{speed},{FIT}[v{j}]")
        labels.append(f"[v{j}]")
    graph = ";".join(chains) + f";{''.join(labels)}concat=n={len(plan)}:v=1:a=0[out]"
    out = HERE / f"coco_{i}.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-filter_complex", graph, "-map", "[out]", "-an",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", str(out)], check=True)
    d = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(out)],
                       capture_output=True, text=True).stdout.strip()
    print(out.name, round(float(d), 1), "s")
