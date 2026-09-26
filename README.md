# DuoAssess

Two-sided movement coaching for iPhone Duo. One person works on the inner display, the other sees
a clean coaching view on the outer display, and folding the phone scrubs the video.

Two modes:

- **Copy me** — two people face each other with the phone between them; the demonstrator's
  display scores how closely the learner matches per limb, the learner's display ghosts the
  demonstrator's pose over their own body (`DuoAssess/CopyMe/`).
- **Assess** — single-person `Profile`s: squat form and facial symmetry (`DuoAssess/Assessment/`).

Every stream runs from a bundled video in `design/` or, when the file is missing, from a
synthetic generator so the app always has something to show. The original furniture placement
prototype is kept under `DuoAssess/Furniture/`.

```bash
tool/run.sh demo      # build, install, launch on the booted iPhone Duo sim, screenshot both displays
xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData
hinge 90              # brew install artemnovichkov/tap/hinge — fold angle drives the playhead
```

See `BUILD_NOTES.md` for the file map, what was verified, assumptions and known gaps.
