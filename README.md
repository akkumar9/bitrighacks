# DuoAssess

Two-sided movement assessment for iPhone Duo. The clinician works on the inner display, the
patient sees a clean coaching view on the outer display, and folding the phone scrubs the video.

Assessments are `Profile`s (see `DuoAssess/Assessment/Profile.swift`): squat form and facial
symmetry ship today. Each runs from a bundled video or, when the file is missing, from a synthetic
generator so the app always has something to show.

```bash
tool/run.sh demo      # build, install, launch on the booted iPhone Duo sim, screenshot both displays
xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData
hinge 90              # brew install artemnovichkov/tap/hinge — fold angle drives the playhead
```

See `BUILD_NOTES.md` for the file map, what was verified, assumptions and known gaps.
