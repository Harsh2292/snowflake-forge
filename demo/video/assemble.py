"""Cut the recording, add cards and narration, and join everything into one MP4.

python assemble.py [audio_dir] [coco_clip ...]
  audio_dir: folder with s1..s6 narration (.wav or .mp3); default ./audio
  coco_clip: optional CoCo CLI recordings for scenes 3a, 3b, 3c (one file each, already trimmed),
             or a single file used for all of scene 3. Without them, a placeholder card is used.
"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
SEG = HERE / "seg"; SEG.mkdir(exist_ok=True)
AUDIO = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "audio_draft"
COCO = [Path(a) for a in sys.argv[2:]]
RAW = HERE / "raw.webm"
M = json.loads((HERE / "marks.json").read_text())
SLIDE_IMPACT = HERE / "impact_slide.png"
FONT = "C:/Windows/Fonts/arialbd.ttf"
FONT_R = "C:/Windows/Fonts/arial.ttf"
VENC = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-r", "30"]
AENC = ["-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2"]


def run(cmd):
    subprocess.run(cmd, check=True, capture_output=True)


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True).stdout.strip()
    return float(out)


def voice(key):
    for ext in (".mp3", ".wav"):
        p = AUDIO / f"{key}{ext}"
        if p.exists():
            return p
    return None


def card(name, title, sub="", dark=True):
    img = Image.new("RGB", (1920, 1080), (11, 18, 32) if dark else (238, 243, 251))
    d = ImageDraw.Draw(img)
    ink = (255, 255, 255) if dark else (11, 18, 32)
    muted = (150, 175, 215) if dark else (91, 107, 130)
    ft, fs = ImageFont.truetype(FONT, 76), ImageFont.truetype(FONT_R, 38)
    tw = d.textlength(title, font=ft)
    d.text(((1920 - tw) / 2, 430), title, font=ft, fill=ink)
    for i, line in enumerate(sub.split("\n") if sub else []):
        w = d.textlength(line, font=fs)
        d.text(((1920 - w) / 2, 560 + i * 58), line, font=fs, fill=muted)
    p = HERE / f"card_{name}.png"
    img.save(p)
    return p


def segment(name, video_inputs, key=None, min_len=0.0, lead=0.6, tail=0.9):
    """video_inputs: list of ('cut', start, end) from RAW, ('img', path, seconds) or ('file', path, None).
    The narration starts `lead` s in; the clip lasts at least voice + lead + tail."""
    parts = []
    for i, (kind, a, b) in enumerate(video_inputs):
        out = SEG / f"{name}_p{i}.mp4"
        if kind == "cut":
            run(["ffmpeg", "-y", "-ss", f"{a:.2f}", "-to", f"{b:.2f}", "-i", str(RAW), "-an",
                 "-vf", "scale=1920:1080,fps=30", *VENC, str(out)])
        elif kind == "img":
            run(["ffmpeg", "-y", "-loop", "1", "-t", f"{b:.2f}", "-i", str(a), "-an",
                 "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=white,fps=30",
                 *VENC, str(out)])
        else:
            run(["ffmpeg", "-y", "-i", str(a), "-an",
                 "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30",
                 *VENC, str(out)])
        parts.append(out)
    lst = SEG / f"{name}_list.txt"
    lst.write_text("".join(f"file '{p.as_posix()}'\n" for p in parts))
    vid = SEG / f"{name}_v.mp4"
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(vid)])
    vlen = dur(vid)
    v = voice(key) if key else None
    need = max(min_len, (dur(v) + lead + tail) if v else 0)
    out = SEG / f"{name}.mp4"
    if need > vlen:  # hold the last frame
        filt_v = f"tpad=stop_mode=clone:stop_duration={need - vlen:.2f}"
        total = need
    else:
        filt_v = "null"
        total = vlen
    if v:
        run(["ffmpeg", "-y", "-i", str(vid), "-i", str(v), "-filter_complex",
             f"[0:v]{filt_v}[v];[1:a]adelay={int(lead*1000)}|{int(lead*1000)},apad,atrim=0:{total:.2f}[a]",
             "-map", "[v]", "-map", "[a]", "-t", f"{total:.2f}", *VENC, *AENC, str(out)])
    else:
        run(["ffmpeg", "-y", "-i", str(vid), "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-filter_complex",
             f"[0:v]{filt_v}[v]", "-map", "[v]", "-map", "1:a", "-t", f"{total:.2f}", *VENC, *AENC, str(out)])
    print(f"{name}: {total:.1f}s")
    return out


segs = []
segs.append(segment("s0", [("img", card("title", "Supply Chain Forge",
                    "One governed number for every team\nSnowflake CoCo CLI Hackathon \u00b7 GCC Edition"), 3.5)]))
segs.append(segment("s1", [("cut", M["s1_start"], M["s1_end"])], "s1"))
segs.append(segment("s2", [("cut", M["s2_start"], M["s2_end"])], "s2"))

if len(COCO) == 3:
    for key, clip in zip(["s3a", "s3b", "s3c"], COCO):
        segs.append(segment(key, [("file", clip, None)], key))
elif len(COCO) == 1:
    # one recording for all of scene 3: the three voice lines play back to back over it
    segs.append(segment("s3", [("file", COCO[0], None)], "s3_all"))
else:
    labels = {"s3a": ("CoCo CLI \u00b7 data-quality skill", "[ your CoCo recording: prompt 1 ]"),
              "s3b": ("CoCo CLI \u00b7 data-governance skill", "[ your CoCo recording: prompt 2 ]"),
              "s3c": ("CoCo CLI \u00b7 agent-studio skill", "[ your CoCo recording: prompt 3 ]")}
    for key, (t, s) in labels.items():
        segs.append(segment(key, [("img", card(key, t, s), 2.0)], key))

segs.append(segment("s4a", [("cut", M["s4a_start"], M["s4a_end"])], "s4a"))
segs.append(segment("s4b", [("cut", M["s4b_start"] + 2.1, M["s4b_asked"] + 1.3),
                            ("cut", M["s4b_answered"] - 5.0, M["s4b_end"])], "s4b"))
segs.append(segment("s5", [("cut", M["s5_start"], min(M["s5_end"], M["s5_start"] + 16.0))], "s5"))
segs.append(segment("s6", [("img", SLIDE_IMPACT, 12.0), ("cut", M["s6_start"] + 1.2, M["s6_end"])], "s6"))
segs.append(segment("s7", [("img", card("end", "supply-chain-forge.streamlit.app",
                    "github.com/Harsh2292/snowflake-forge\nThank you"), 4.0)]))

lst = SEG / "all.txt"
lst.write_text("".join(f"file '{p.as_posix()}'\n" for p in segs))
final = HERE / "Supply_Chain_Forge_Demo.mp4"
run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", "-movflags", "+faststart", str(final)])
print(f"FINAL {final} {dur(final):.1f}s")
