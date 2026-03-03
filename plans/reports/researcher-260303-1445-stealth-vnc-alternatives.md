# Stealth Remote Screen Viewing — macOS 15 Apple Silicon Research
**Date:** 2026-03-03
**Context:** Lucy (macOS 15.6.1, Apple Silicon, Homebrew, pyobjc-framework-Quartz confirmed working)

---

## Critical Background: The Indicator Problem

macOS 15 (Sequoia) enforces screen-recording indicators through `systemstatusd` daemon:
- **ScreenCaptureKit** (SCStream, SCScreenshotManager) — **always shows** Video menu bar item + live preview per active stream
- **CGDisplayCreateImage / CGDisplayStream** — **obsoleted** in macOS 15.0, throws at link time
- **CGWindowListCreateImage** — deprecated since macOS 14, **still callable** via Python pyobjc on macOS 15 (confirmed by existing `mac live` command working). **Crucially: does NOT show the orange/purple ControlCenter dot.** The dot is tied to ScreenCaptureKit sessions and microphone/camera APIs, not to `CGWindowListCreateImage` polling.
- Hiding the dot without SIP disabled: **not possible** (Apple patched every known method by macOS 12.2)
- Apple's official method: hide on external display only (`system-override suppress-sw-camera-indication-on-external-displays=on`) — not main display

**Key insight already proven:** `mac live` uses `CGWindowListCreateImage` via SSH with no indicator. This is the stealth baseline.

---

## Option 1: libvncserver / macVNC

**Project:** [LibVNC/macVNC](https://github.com/LibVNC/macVNC) — command-line VNC server for macOS

**Status:** Actively maintained. Dec 22, 2024 commits ported screen capture from `CGDisplayStream` → **ScreenCaptureKit**.

**Installation:**
```bash
brew install libvncserver cmake
git clone https://github.com/LibVNC/macVNC && cd macVNC
mkdir build && cd build && cmake .. && cmake --build . && cmake --install .
macvnc -passwd secret &
```

**Capture API (post Dec 2024):** ScreenCaptureKit (SCStream)
- **Indicator:** YES — SCStream always registers with ControlCenter's Video menu. Will show screen-recording indicator in menu bar.
- **Performance:** Full VNC, should support up to 30fps, hardware compositing, proper diff updates
- **Control mode:** Yes — mouse + keyboard input via macOS accessibility API
- **SSH tunnel:** Yes — `ssh -L 5901:localhost:5900 lucy` then connect VNC client to localhost:5901
- **Apple Silicon / macOS 15:** Builds and works (ScreenCaptureKit is the required path on macOS 15)

**Verdict:** BEST quality + control, but **not stealth** — shows indicator. Works great for `mac screen` scenario (when you know user is away).

---

## Option 2: TigerVNC Server on macOS

**Project:** [TigerVNC](https://github.com/TigerVNC/tigervnc) via `brew install tiger-vnc`

**macOS server reality:** TigerVNC on macOS only ships the **viewer** binary (vncviewer). The server components (`Xvnc`, `x0vncserver`) are Linux-only — they require X11/Xorg which does not exist on macOS natively.

**No native macOS screen capture mode.** The Homebrew formula `tiger-vnc` installs only the client.

**Verdict:** Not applicable for macOS as a server. Dead end.

---

## Option 3: x11vnc on macOS

**Project:** [Apreta/x11vnc-macosx](https://github.com/Apreta/x11vnc-macosx) (fork of LibVNC/x11vnc)

**Reality:**
- x11vnc has a `--without-x` build mode that uses macOS CoreGraphics (`CGDisplayCreateImage`) directly
- The macOS fork adds HiDPI support and OS-level change detection
- **However:** Last commit April 2016 — 9+ years abandoned
- `CGDisplayCreateImage` is **obsoleted** in macOS 15.0 — will fail to compile or crash at runtime
- Build: `./configure --without-x --without-ssl && make` — will fail on macOS 15 SDK

**Verdict:** Dead — obsolete API, abandoned project, won't build on macOS 15.

---

## Option 4: Custom Python VNC Server (pyobjc + RFB)

**Approach:** Python script implementing RFB protocol using pyobjc Quartz for capture + `PyVNCServer` or hand-rolled RFB server.

**Components available:**
- `PyVNCServer` ([xulek/PyVNCServer](https://github.com/xulek/PyVNCServer)) — pure Python RFB server with Raw/Hextile/ZRLE/JPEG encodings, Python 3.13+ support, uses `mss` for capture by default
- Lucy already has `pyobjc-framework-Quartz` — can replace `mss` with `CGWindowListCreateImage` for capture
- RFB protocol is straightforward to implement in Python for a minimal server

**Indicator:** `CGWindowListCreateImage` does NOT trigger ControlCenter indicator (proven by existing `mac live`). A Python VNC server using this API would be fully stealth.

**Feasibility:** Medium complexity. PyVNCServer needs `mss` replaced with pyobjc capture. Must also handle:
- Diff/dirty-rect encoding (otherwise huge bandwidth at 30fps)
- Mouse/keyboard input injection via `CGEvent` (already proven working in `mac screen`)
- Running as background daemon via SSH

**Performance estimate:** 5–15fps realistic (Python overhead for frame diffing), possibly 20fps+ with JPEG compression and frame skipping. Not 60fps.

**SSH tunnel:** Yes — bind to localhost only, forward port via SSH.

**Control mode:** Yes — CGEvent keyboard+mouse injection already proven.

**Build/Install:**
```bash
pip3 install PyVNCServer  # or git clone + install
# Then custom wrapper script integrating CGWindowListCreateImage
```

**Verdict:** Most stealth option with mouse/keyboard control. Medium build effort. 5–20fps. Requires custom integration work.

---

## Option 5: ffmpeg AVFoundation → SSH pipe → ffplay

**Approach:** Run `ffmpeg -f avfoundation -i "1:none"` on Lucy via SSH, pipe H.264 stream to local `ffplay`.

**Command pattern:**
```bash
# On David's Mac:
ssh lucy "ffmpeg -f avfoundation -framerate 30 -capture_cursor 1 \
  -i '1:none' -vcodec h264_videotoolbox -b:v 2M \
  -preset ultrafast -tune zerolatency -f mpegts -" \
  | ffplay -fflags nobuffer -framedrop -window_title "Lucy" -i -
```

**Indicator:** UNKNOWN definitively, but likely YES. AVFoundation screen capture uses the same system permission (`com.apple.screencapture`) as ScreenCaptureKit. macOS 15 shows the indicator for any process with an active AVFoundation screen session. Needs empirical testing on Lucy to confirm.

**Performance:** This is the highest-potential option:
- h264_videotoolbox = Apple Silicon GPU hardware encoder, near-zero CPU
- Realistic 25–30fps over LAN SSH with 2–4 Mbps bitrate
- Latency: ~200–500ms (encoding + SSH pipe buffering)
- Over CF tunnel: 5–15fps, ~1s latency

**Control mode:** ffplay is view-only. To add control, would need a separate CGEvent injection channel (same SSH session, separate command).

**Installation on Lucy:**
```bash
brew install ffmpeg  # ~500MB, includes avfoundation support
```

**SSH pipe quality:** Proven approach (SSH stdout pipe → local ffplay). The NUT/mpegts container works well for piped streams.

**Verdict:** Best performance potential (30fps LAN), hardware-accelerated, but indicator status unconfirmed. View-only unless combined with existing CGEvent control. Simple to implement if indicator is not a concern.

---

## Option 6: Enhanced `mac live` — Upgrade Existing Approach

**Current state:** `mac live` already works, uses `CGWindowListCreateImage`, confirmed stealth, 3–7fps.

**Improvement options without changing the stealth guarantee:**

### 6a. Frame Differencing + MJPEG
Add dirty-rect detection — only transmit changed regions. Current code sends full JPEG every frame. With numpy diff:
- Could reduce bandwidth 5–10x on mostly-static screens
- Enables higher fps (15–20fps) without more bandwidth

### 6b. Switch to ffplay with MJPEG framing
Current approach pipes raw JPEGs concatenated. ffplay's MJPEG demuxer works but needs proper MJPEG framing. The current implementation already uses `-f mjpeg` in ffplay — this is correct.

### 6c. Increase FPS — LAN is capable of more
Current LAN setting: `FPS="0.15"` (delay between frames, so ~6fps). Could push to `FPS="0.05"` = ~20fps for LAN. The bottleneck is Python's `CGWindowListCreateImage` call speed (~50–100ms per frame on Apple Silicon).

### 6d. Hardware-assisted JPEG via ImageIO
Replace pure-Python JPEG encoding with CoreFoundation's `CGImageDestination` (already used) — this IS hardware-assisted on Apple Silicon. Current implementation already does this correctly.

**Verdict:** Simplest path to improvement. No new dependencies, guaranteed stealth, 15–20fps achievable on LAN. Recommend as primary upgrade.

---

## Comparison Matrix

| Option | Stealth | Max FPS (LAN) | Control | Complexity | macOS 15 Status |
|--------|---------|---------------|---------|------------|-----------------|
| 1. macVNC (libvncserver) | NO (SCStream indicator) | 30+ | Yes | Low | Works |
| 2. TigerVNC server | N/A | N/A | N/A | N/A | Not available |
| 3. x11vnc macOS | Yes (CGDisplayCreateImage) | ~15 | Yes | High | BROKEN (obsolete API) |
| 4. Python VNC server (pyobjc) | YES | 5–20 | Yes | Medium | Works |
| 5. ffmpeg AVFoundation | Unconfirmed | 25–30 | View-only | Low | Works (needs brew install) |
| 6. Enhanced mac live | YES (proven) | 15–20 | Yes (CGEvent) | Low | Works today |

---

## Recommendations

### If stealth is non-negotiable:

**Priority 1 — Enhance `mac live` (Option 6):** Increase LAN fps to 15–20fps by reducing delay to 0.05s. Zero new deps, proven working.

**Priority 2 — Python VNC server (Option 4):** Full RFB protocol with mouse/keyboard control, stealth via `CGWindowListCreateImage`. Build a minimal Python VNC server that wraps the existing capture code. This gives proper VNC client compatibility (no need for ffplay).

### If stealth is not needed (user is away/asleep):

**Option 1 (macVNC):** Best VNC experience — proper 30fps, all VNC clients work, SSH-tunnable. Accepts the indicator showing in menu bar.

**Option 5 (ffmpeg):** Best raw performance for view-only streaming over LAN. Low setup effort if ffmpeg is installed. Add CGEvent control via separate SSH channel.

### Recommended immediate action:

Test ffmpeg indicator behavior on Lucy first (quick test, high value):
```bash
ssh lucy "brew install ffmpeg && ffmpeg -f avfoundation -framerate 5 -i '1:none' -vcodec h264_videotoolbox -f mpegts - 2>/dev/null" | ffplay -fflags nobuffer -i - &
# Observe: does menu bar indicator appear on Lucy?
```

If no indicator → ffmpeg becomes the best overall option (30fps, hardware H.264, simple).
If indicator appears → stick with Python/CGWindowListCreateImage path.

---

## Unresolved Questions

1. **Does ffmpeg AVFoundation show ControlCenter indicator on macOS 15?** Not confirmed by any source — needs empirical test on Lucy. AVFoundation uses a different permission path than ScreenCaptureKit's SCStream — it's possible it doesn't trigger the "Video" menu bar item.

2. **Does `CGWindowListCreateImage` still work on macOS 15.6.1?** Deprecated since macOS 14, obsoleted in macOS 15 release notes — but `mac live` is confirmed working. The API is deprecated but not removed from the dylib in practice. May be removed in a future minor update.

3. **Python VNC server `mss` vs pyobjc on macOS 15:** `mss` on macOS uses CGDisplayCreateImage which IS obsoleted. Using pyobjc `CGWindowListCreateImage` as replacement needs testing in PyVNCServer's capture path.

4. **macVNC ScreenCaptureKit indicator behavior over SSH:** Does the Video menu bar indicator still appear when macVNC runs as a daemon (no GUI process)? Possible it's suppressed without a `NSRunLoop` GUI context — needs testing.

---

## Sources
- [LibVNC/macVNC](https://github.com/LibVNC/macVNC)
- [Alin Panaitiu — Can we hide the orange dot without SIP](https://notes.alinpanaitiu.com/Can-we-hide-the-orange-dot-without-disabling-SIP)
- [Apple — Hide privacy indicators on external displays](https://support.apple.com/en-us/118449)
- [ffmpeg AVFoundation documentation](https://ffmpeg.org/ffmpeg-devices.html)
- [Hardware Acceleration FFmpeg Apple Silicon](https://codetv.dev/blog/hardware-acceleration-ffmpeg-apple-silicon)
- [SSH Media Pipe Gist](https://gist.github.com/yuvadm/29b8addccbbc376b5bb5)
- [PyVNCServer](https://github.com/xulek/PyVNCServer)
- [macOS Sequoia monthly screen recording prompts](https://lapcatsoftware.com/articles/2024/8/10.html)
- [ScreenCaptureKit WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [CGWindowListCreateImage → ScreenCaptureKit Apple Forums](https://developer.apple.com/forums/thread/740493)
