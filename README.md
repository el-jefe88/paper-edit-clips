# Paper Edit → Clips

Tools for turning a paper edit (a list of clock-time in/out points) into DNxHR clips ready for DaVinci Resolve on Linux. Two ways to work: a **terminal-only workflow** (durable — plain text files, nothing lost if a browser tab closes) and a **browser app** (visual, good for reviewing a long list). Both produce the same CSV format and the same `ffmpeg` commands.

**Currently in active use** — logging and transcoding footage for a live edit, discarding segments as the cut narrows.

**If you've had data disappear on you before, use the terminal workflow below — it's the recommended path.** A CSV file on disk survives reboots, different browsers, private windows, and cache clears. Browser local storage does not.

---

## Terminal-only workflow (recommended)

Three steps: log clips → convert → verify. No browser required at any point.

### 1. Log each clip segment

```bash
./log_clip.sh clips.csv "/path/to/source.mp4" 00:03:05 00:03:15
```

Run this once per in/out point. For a clip with several selects from the same source file, just call it again with the same source — output names auto-number (`sourcename_seg1`, `sourcename_seg2`, ...). Give a 5th argument to override the auto name:

```bash
./log_clip.sh clips.csv "/path/to/source.mp4" 00:05:00 00:05:25 dance_intro
```

Every call appends one row to `clips.csv` (created automatically on first use) — check it anytime with `cat clips.csv`, or edit it directly in `nano`/`vim` if you want to fix a typo or reorder rows.

### 2. Convert to DNxHR

```bash
./extract_clips.sh clips.csv /path/to/output --preset hq
```

| Flag | Values | Effect |
|---|---|---|
| `--preset` | `lb`, `sq`, `hq` (default), `hqx` | Which DNxHR quality tier to render — see table below |
| `--also-hq` | (no value) | Also render a Full Quality (`dnxhr_hq`) pass alongside whatever `--preset` you chose, into its own subfolder |

Quality presets (same as the browser app):

| Preset | `-profile:v` | Pixel format | Use for |
|---|---|---|---|
| `lb` | `dnxhr_lb` | `yuv422p` | Small, fast-scrubbing proxies |
| `sq` | `dnxhr_sq` | `yuv422p` | Light offline editing |
| `hq` | `dnxhr_hq` | `yuv422p` | Full quality, edit-and-deliver (the default) |
| `hqx` | `dnxhr_hqx` | `yuv422p10le` | 10-bit finishing/mastering |

Each preset writes into its own subfolder (`proxy_lb/`, `offline_sq/`, `dnxhr_hq/`, `dnxhr_hqx/`) under the output directory you give, so a proxy pass and a full-quality pass of the same list never collide:

```bash
# proxies now, full-quality masters at the same time
./extract_clips.sh clips.csv /path/to/output --preset lb --also-hq
```

### 3. Verify before trusting the whole batch

```bash
ls -lh /path/to/output/dnxhr_hq/
ffprobe -hide_banner -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,pix_fmt,width,height,r_frame_rate \
  /path/to/output/dnxhr_hq/your_clip_seg1.mov
```

You want `codec_name=dnxhd`, `pix_fmt=yuv422p` (or `yuv422p10le` for `hqx`), and a resolution/frame rate matching your source.

Then import into Resolve: **Media page → Media Storage panel (bottom-left) → navigate to your output subfolder → drag clips into the Media Pool.** Clean thumbnails with no red X confirm DNxHR decoded correctly.

---

## Browser app (alternative / visual review)

`paper_edit_csv.html` does the same logging and generation with a form, a running table, and one-click copy/download. Its CSV and generated commands are identical in format to the terminal tools, so you can mix and match.

**Its one weak point:** the segment list only persists in that specific browser's local storage. If you want something that survives browser changes, use `log_clip.sh` instead — same result, plain text file.

---

## Running the browser app locally, next to your footage

### Option A — just double-click it (simplest)

Copy `paper_edit_csv.html` into your shoot/footage folder and open it directly in a browser.

**Caveat:** some browsers restrict Clipboard/download access on `file://` pages. If Copy or Download don't respond, use Option B.

### Option B — serve it locally (recommended, still fully offline)

```bash
cd /path/to/your/footage
python3 -m http.server 8000
```

Then open `http://localhost:8000/paper_edit_csv.html`. Stop the server with `Ctrl+C` when done.

---

## Files in this kit

| File | Purpose |
|---|---|
| `log_clip.sh` | Terminal tool — appends one in/out segment to a CSV. |
| `extract_clips.sh` | Terminal tool — transcodes every CSV row to DNxHR. |
| `paper_edit_csv.html` | Browser app — visual alternative, same format. |
| `clips_example.csv` | Example CSV showing the expected format. |
| `README.md` | This file. |

---

## Typical workflow

```bash
chmod +x log_clip.sh extract_clips.sh
./log_clip.sh clips.csv "/path/to/source.mp4" 00:03:05 00:03:15
./log_clip.sh clips.csv "/path/to/source.mp4" 00:05:00 00:05:25
./extract_clips.sh clips.csv /path/to/output --preset lb --also-hq
```

The extraction script reports success/failure per line and skips missing sources or invalid in/out pairs rather than halting the whole batch.

---

## Notes

- Timecodes are **clock time**, not frame-based. Convert frame timecode to `HH:MM:SS.mmm` first if needed.
- `-ss` is applied before `-i` for fast, accurate seeking on re-encodes.
- Output filenames are sanitized automatically.
- Both scripts handle paths with spaces correctly when quoted as shown above.
