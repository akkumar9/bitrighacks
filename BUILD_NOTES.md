# DuoAssess — build notes

Two assessment profiles (squat form, facial symmetry) behind one `Profile` protocol, running on
the two-sided iPhone Duo architecture: clinician on the inner display split across the fold,
patient on the outer display, hinge scrubs the video. Simulator only (Xcode 27.1 beta, iOS 27.1).
No videos have landed; everything below ran on the synthetic generators.

```bash
tool/run.sh demo          # build, install, launch on the booted iPhone Duo sim, screenshot both displays
xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData
hinge open | hinge 130 | hinge close | hinge sweep 170 30 3
```

Display mapping for `simctl io` (verify with `simctl io "iPhone Duo" enumerate`):
`--display=primary-1` is the inner display, `--display=primary` is the outer, and the outer is also
the default when no display is given.

## When the videos land

Drop `design/squat.mp4` and `design/face.mp4` in and rebuild. `SessionModel.source(for:)` picks the
video over the synthetic generator per profile; a missing or unreadable file falls back to synthetic
and the status badge shows the error. Then check, per profile:

1. Status badge says `squat.mp4` / `face.mp4`, not `synthetic`.
2. The overlay sits on the person. Rotated 90°: flip `VideoEngine.applyPreferredTransform`.
   Mirrored: for the squat, swap left/right in `SquatProfile.jointMap`; for the face nothing changes,
   `FaceGeometry.mouthCorners` picks the left corner by the left eye's x.
3. "frames analysed" climbs while playing. Vision runs on the CPU in the simulator; if it stalls
   the display link skips frames by design, so the timeline gets sparser, not slower.
4. Retune thresholds with the deck sliders (they re-run the analysis live) and copy the numbers
   into `SquatThresholds` / `FaceThresholds` defaults.
5. Face: watch "Baseline n/20" in the metrics. It restarts whenever the mouth jumps during
   calibration, so the clip must open with a second of a relaxed face.

## File map

| File | What it does |
|---|---|
| `DuoAssess/DuoAssessApp.swift` | `@main`, `RootView` (owns `SessionModel`, `.sceneAccessory` for the outer display, hinge hook, fallback patient pane when the accessory is unavailable). |
| `DuoAssess/OuterDisplayView.swift` | Rotates any content -90° for the outer framebuffer. |
| `Assessment/Profile.swift` | `Metric`, `Cue`, `Overlay`, `Readout`, `ThresholdControl`, `LogEntry`, the `Profile` protocol. |
| `Assessment/SessionModel.swift` | Shared `@Observable` session: profiles list, current profile, engine lifecycle, transport, hinge → scrub, readout refresh, video-failure fallback. |
| `Assessment/AssessmentEngine.swift` | Engine protocol and delegate, `ProfileSink` (routes frames to the current profile off the main thread), `SyntheticEngine`. |
| `Assessment/VideoEngine.swift` | AVPlayer + AVPlayerItemVideoOutput + CADisplayLink; one frame in flight, skipped not queued; orientation from the track's preferredTransform. |
| `Assessment/SquatProfile.swift` | Adapter over the pose math; owns `VNDetectHumanBodyPoseRequest`. |
| `Assessment/PoseTypes.swift`, `PoseGeometry.swift`, `PoseSmoothing.swift`, `RepCounter.swift`, `SquatAnalyzer.swift`, `SyntheticSquat.swift` | Squat math, unchanged from the prototype. |
| `Assessment/FaceSymmetryProfile.swift` | Adapter over the face math; owns `VNDetectFaceLandmarksRequest`, converts bounding-box points to image space. |
| `Assessment/FaceGeometry.swift` | `FaceLandmarks`, `FaceThresholds`, `FaceMeasures`, `FaceMetrics`, pure functions (interocular normalization, corners, brows, apertures, midline fit, score, affected side). |
| `Assessment/GestureCounter.swift` | rest → onset → peak → release → rest; discards onsets that never peak. |
| `Assessment/FaceAnalyzer.swift` | `Timeline<T>`, moving-average smoothing, baseline calibration, metrics, gesture counting over a time-ordered list. |
| `Assessment/SyntheticFace.swift` | Deterministic landmark generator with a right-sided deficit. |
| `Assessment/StageView.swift` | `StageGeometry` (letterbox + y-flip), `StageView`, `OverlayView` (skeleton / face / none), `PlayerLayerView`, `StudioBackdrop`. |
| `Assessment/ClinicianView.swift` | `ArrangementView` split across the fold: picture + metrics on one half, `ControlDeck` on the other; VStack when there is no fold. |
| `Assessment/PatientView.swift` | Picture, big count, `CueLabel`, `TargetBar`. |
| `Assessment/HingeScrub.swift` | `.hingeScrub(session)` around `onHingeChange`. |
| `DuoAssessTests/*` | 52 Swift Testing cases. |
| `tool/gen-project.py`, `tool/run.sh` | Project generator (synchronized folders, no pbxproj edits needed) and build/run/screenshot script. |

## Verified (simulator, synthetic data)

- 52/52 tests: squat suites (27, unchanged), face geometry, gesture counter, face analyzer,
  engines and profile readouts.
- Profile swap in the deck picker: face profile takes over both displays, squat comes back and
  re-analyses (`screenshots/stage3-face-synthetic-*.png`).
- Inner display split across the fold in Open and Book poses; deck stacks under the picture on the
  outer display in Closed pose (`screenshots/stage5-*.png`).
- Outer display re-renders the patient view after every view change (count and cue advance between
  screenshots, so it is not a stale frame).
- Hinge scrub still maps 30°…170° to the clip; Play resumes.
- Face on synthetic: calibrates in 20 frames, counts 4 smiles in 13 s, flags the right side on each.

## Assumed

- **Fold orientation.** Measured on the simulator's landscape inner display: a vertical 40 pt band
  at x ≈ 455…495 of 951, active only in Book pose. So "above/below the fold" became left/right, and
  the split axis is `.horizontal`. `.vertical` hid the secondary pane on this display even with a
  bounded primary.
- **The fold-split view is swapped for a VStack** when no division region exists (Closed pose,
  non-Duo). That swap resets view identity, but all state lives on the model.
- **`gesturePeakExcursion` (0.06)** was added to `FaceThresholds` so an onset must reach a real peak
  before it counts, mirroring the squat's bottom threshold.
- **Symmetry score** = 100 × (1 − (0.5·|Δmouth| + 0.3·|Δbrow| + 0.2·|Δeye|) / 0.15), clamped at 0.
  Weights and the 0.15 zero point are `FaceGeometry.weights` / `zeroScoreDifference`.
- **Affected side** = the side whose weighted movement is smaller by more than `asymmetryFlag`.
- **Eye aperture** is the vertical extent of the eye region, not strictly the lid gap at the
  horizontal centre.
- **Overlay coordinates** are normalized image space, origin bottom-left (Vision), converted by
  `StageGeometry` at draw time.
- **Product renamed to DuoAssess** (bundle id `com.duohack.duoassess`). The furniture prototype's
  views were not brought over.
- Scrubbing re-analyses out-of-order frames by keeping a time-sorted timeline per profile and
  re-running the whole analysis on each ingest (a few hundred frames; cheap).

## Known gaps

- Neither video engine path has seen a real file. Orientation handling and Vision throughput are
  the unknowns.
- The face profile's baseline uses the first stable frames of the clip; there is no per-gesture
  re-baselining. "Recalibrate" drops frames before the playhead and re-collects.
- Vision face landmarks have one confidence for the whole set; per-point confidence is not used.
- `Overlay` and `Readout` are not `Equatable` (tuples), so views redraw on every refresh.
- Deprecated `copyPixelBuffer(forItemTime:)` / `init(pixelBufferAttributes:)` still used.
- The patient's target bar for the face is mouth excursion over twice the peak threshold; for the
  squat it is depth. Neither is clinically calibrated.
