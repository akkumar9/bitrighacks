# DuoAssess

Two-sided movement assessment for iPhone Duo. The clinician works on the inner display while the patient sees a clean, distraction-free coaching view on the outer display — folding the phone scrubs the video, so review happens naturally as part of the motion instead of through a separate scrubber UI.

## What it does

- **Two audiences, one device.** Inner display: full clinical view, frame data, annotations. Outer display: patient-facing coaching view, no jargon.
- **Fold-driven scrubbing.** The hinge angle drives the video playhead directly — fold through a rep the same way you'd rewind it.
- **Pluggable assessments.** Assessments are `Profile`s (see [`DuoAssess/Assessment/Profile.swift`](DuoAssess/Assessment/Profile.swift)). Squat form and facial symmetry ship today.
- **Never a blank screen.** Each profile runs from a bundled reference video or, if that file is missing, from a synthetic generator — the app always has something to show.

## Quickstart

```bash
# Build, install, launch on the booted iPhone Duo simulator, and screenshot both displays
tool/run.sh demo

# Run the test suite
xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData

# Drive the fold angle manually (brew install artemnovichkov/tap/hinge)
hinge 90
```

## Learn more

See [`BUILD_NOTES.md`](BUILD_NOTES.md) for the full file map, what's been verified, assumptions made, and known gaps.
