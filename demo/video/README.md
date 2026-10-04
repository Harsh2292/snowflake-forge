# Demo video assembly (resume here in a new session)

State on 4 Oct 2026: the app scenes are recorded (`raw.webm`, scene times in `marks.json`) and a
draft with the Windows voice is in the user's Downloads (`Supply_Chain_Forge_Demo_DRAFT.mp4`).

Waiting on the user:
1. The CoCo CLI recording (scene 3): one long file, or three files (prompts 1, 2, 3).
2. Nine ElevenLabs MP3s named `s1, s2, s3a, s3b, s3c, s4a, s4b, s5, s6`
   (lines in `../VOICE_LINES.txt`).

Then:
1. Cut the waiting out of the CoCo recording: extract frames with ffmpeg to find where each
   prompt starts and its answer finishes, and trim to three clips, each about as long as
   its voice line (s3a ~19 s, s3b ~22 s, s3c ~21 s of speech; speed up long waits with
   `setpts`). Save the clips as `coco_1.mp4`, `coco_2.mp4` and `coco_3.mp4`.
2. Run from this folder, with any Python that has Pillow, and with ffmpeg on PATH:
   `python assemble.py <folder with the 9 MP3s> coco_1.mp4 coco_2.mp4 coco_3.mp4`
3. Check frames and length (3–5 min), then copy `Supply_Chain_Forge_Demo.mp4` to Downloads.

`record_app.py` re-records the app scenes from the live link if ever needed (Playwright).
Large files are git-ignored.
