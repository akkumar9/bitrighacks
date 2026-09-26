# DuoAssess — build notes

Three things live in this repo, all on the same two-sided iPhone Duo structure (shared
`@Observable` model, `.sceneAccessory` for the outer display, fallback pane when the accessory is
unavailable, hinge → scrub):

1. **Copy me** (default mode) — two people, two cameras (bundled videos for now), pose matching.
2. **Assess** — single-person profiles: squat form, facial symmetry.
3. **Furniture** — the original placement prototype (`FurnitureRootView`, not on the mode switch).

Simulator only (Xcode 27.1 beta, iOS 27.1). No videos have landed; every screenshot below is from
the synthetic generators.

```bash
tool/run.sh demo          # build, install, launch on the booted iPhone Duo sim, screenshot both displays
xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData
hinge open | hinge 130 | hinge close | hinge sweep 170 30 3
```

`simctl io` display mapping: `--display=primary-1` is the inner display, `--display=primary` the
outer (and the default). `axe` touches reach the inner UI only in Closed pose.

## When the videos land

Drop `design/demo.mp4` and `design/learner.mp4` (copy me) and/or `design/squat.mp4`, `design/face.mp4`
(assess) in and rebuild. Each stream/profile falls back to synthetic on its own when its file is
missing. Then:

1. Status badge shows the file names, not `synthetic`.
2. Skeletons sit on the people. Rotated 90°: `VideoPoseStream.applyPreferredTransform`. Mirrored
   footage: flip the deck's **Mirrored** toggle first; if that fixes it, the cameras are not facing
   each other the way the default assumes.
3. Match score is not stuck near 0. If it is, the mirror flag is backwards (every limb reads as
   maximum error). If it is stuck near 100, `minConfidence` is dropping joints and only the torso is
   being compared.
4. Lag reads a plausible fraction of a second. If it pins at `maxLag`, widen the window.
5. "frames analysed" climbs for both streams. Two Vision requests share the M1's CPU in the sim;
   frames are skipped by design, so the timeline gets sparser, not slower.

## File map

| File | What it does |
|---|---|
| `DuoAssess/DuoAssessApp.swift` | `@main`, `AppMode`, `RootView` (both sessions, mode picker, `.sceneAccessory`, hinge routing to the active session, `FallbackOuterPane`). |
| `DuoAssess/OuterDisplayView.swift` | Rotates any content -90° for the outer framebuffer. |
| `CopyMe/PoseStream.swift` | `Role`, `PoseStream` protocol, `VideoPoseStream` (own AVPlayer, video output, display link, Vision request and queue per stream; one frame in flight), `SyntheticPoseStream` (learner = demonstrator mirrored, 300 ms late, one wrist off), `PoseFrame.mirrored()`, `Joint.mirrored`. |
| `CopyMe/CopyMeSession.swift` | Two streams, shared clock, play/pause/seek both, `MatchThresholds`, smoothed `MatchResult`, hinge → seek both. |
| `CopyMe/PoseMatch.swift` | Pure comparison: `LimbAngle`, `MatchThresholds` (weights, score mapping), `JointError`, `MatchResult`, `NormalizedSkeleton`, `PoseMatch` (normalize, angles, compare, lag search, ghost), `MatchSmoother`. |
| `CopyMe/CopyMeViews.swift` | `SkeletonCanvas`, `StreamStage`, `LearnerView` (outer), `CopyMeClinicianView`/`CopyMeAboveFold`/`MatchPanel`/`CopyMeDeck` (inner). |
| `Assessment/FoldSplit.swift` | ArrangementView split across the fold, VStack where no fold exists. Used by both clinician views. |
| `Assessment/PoseTypes.swift` | `Joint`, `JointPoint`, `PoseFrame`, `Skeleton` (struct: joints + bone list), `PoseTimeline`. |
| `Assessment/PoseGeometry.swift`, `PoseSmoothing.swift`, `RepCounter.swift`, `SquatAnalyzer.swift`, `SyntheticSquat.swift` | Squat math, unchanged. |
| `Assessment/Profile.swift`, `SessionModel.swift`, `AssessmentEngine.swift`, `VideoEngine.swift`, `SquatProfile.swift`, `FaceSymmetryProfile.swift`, `FaceGeometry.swift`, `GestureCounter.swift`, `FaceAnalyzer.swift`, `SyntheticFace.swift`, `StageView.swift`, `ClinicianView.swift`, `PatientView.swift`, `HingeScrub.swift` | The assessment profiles (see git history for their notes). |
| `Furniture/*` | The furniture build, intact. |
| `DuoAssessTests/PoseMatchTests.swift` | 10 copy-me tests. 62 in total across 9 suites. |
| `tool/gen-project.py`, `tool/run.sh` | Project generator (synchronized folders; no pbxproj edits) and build/run/screenshot script. |

## What was run and screenshotted

- 62/62 tests (`xcodebuild test`): identical skeletons → 100 with no bad joints; mirrored pose with
  `mirrored == true` → 100; same pose with `mirrored == false` → score < 80 with a bad joint; 2×
  scaled and translated skeleton → 100 and the ghost's hips land on the learner's hips; 30° on one
  elbow → only that limb flagged, `worst` names it; learner 400 ms late → lag 0.400 s and score > 95
  while frame-to-frame scores lower; missing/low-confidence skeleton → `isValid == false`; squat,
  face, engine suites unchanged and green.
- Copy me on synthetic data, Open pose: inner shows score 90, worst = left elbow (~49°, the injected
  wrist offset), lag 0.30 s (the injected delay); outer shows the learner with the orange ghost
  over the cyan skeleton, the offset wrist ringed red, cue "Fix your left elbow"
  (`screenshots/copyme-open-*.png`; the two outer captures differ, so it is live, not stale).
- Book pose: split with the fold band visible (`copyme-book-inner.png`). Closed pose: stacked layout
  on the outer display, learner pane below (`copyme-closed-outer-stacked.png`).
- Mode switch to Assess in Closed pose swaps both surfaces to the squat profile
  (`copyme-closed-mode-switched-to-assess.png`) and back.
- Hinge: 100° → both streams at 4.96 s, 60° → 2.26 s (`copyme-hinge-100deg-*.png`).

## Decisions made without confirmation

- **Repo layout.** Built in `~/bitrighacks` (already the push target, already holding the
  generalized assessment code) rather than a fresh copy of `~/duo-hack/DuoFurnish`; the furniture
  build was restored from there under `DuoAssess/Furniture` as asked. Product name stays DuoAssess.
- **Copy me is a mode next to the assessments**, not a `Profile`: it needs two streams, which the
  single-stream `Profile` contract does not express. `AppMode` in `RootView` switches views inside
  one tree; only the active session runs.
- **Score mapping:** 100 × (1 − weighted-mean-error / 60°), clamped. `goodJointError` only decides
  the per-joint "good" colour, so one bad limb always costs score (a flat band under 10° let a 30°
  elbow error still read 100). Weights: arms/shoulders 1.0, knees/hips 0.8, torso 1.2, in
  `MatchThresholds.weights`.
- **`JointError.limb` names the learner's limb** (what they must fix). With mirroring, the learner's
  right elbow is scored against the demonstrator's left elbow.
- **Lag search** samples `[t − maxLag, t]` at `lagSearchStride` using the nearest timeline frame,
  keeps the best score, and only replaces on a strictly better score, so ties resolve to the
  smallest lag.
- **Smoothing** is a moving average over the last `smoothingWindow` valid results (score, lag,
  per-joint error); the bad flag is re-evaluated on the averaged error; invalid results pass
  through without touching the window.
- **Synthetic learner** = demonstrator mirrored, delayed 0.3 s, left wrist pushed +0.07/+0.03.
- **Hinge smoothing** for scrubbing is a 0.5° dead band plus first-sample calibration, the same
  guard the assessment session uses; the reveal-style `withAnimation` does not apply to a seek.
- **Shared clock** follows the demonstrator's stream; duration is the shorter of the two clips.
- **Torso lean** is the unsigned angle from vertical, so it is mirror-invariant by construction.
- **Fold axis is horizontal** (the fold is a vertical band on this landscape display); "above/below
  the fold" became left/right.

## Fragile

- `VideoPoseStream` has never run on a real file. Orientation and two-request CPU load are unknowns.
- Two synthetic streams run on two timers and can drift a frame apart; the video path drifts too
  (two AVPlayers). There is no cross-stream clock sync beyond seeking both to the same time.
- Stream failure only reports an error; it does not yet swap that stream for synthetic (TODO in
  `CopyMeSession`).
- The closed-pose portrait layout is functional but cramped; the mode picker sits over the stage.
- Vision body pose for two people on one CPU in the simulator may not hold 30 fps; expect sparse
  timelines and a lag estimate quantized to whatever frames exist.
- `Overlay`/`MatchResult` drive redraws on every frame; fine at 30 fps, untested under load.

## Three things most likely to be wrong

1. **The mirror default.** If the real cameras are not literally facing each other (e.g. both
   people face the same way, or one video is mirrored by the recorder), every rep reads as maximum
   error. The deck toggle is the first thing to flip.
2. **Angle-only comparison from a 2D oblique camera.** The two cameras see the two people from
   different angles, and a 2D limb angle changes with viewpoint. Expect a constant error floor
   that has nothing to do with the copy; `zeroScoreError` and the weights will need retuning.
3. **Lag window and stride.** 1 s / 33 ms works for the synthetic 0.3 s delay. Real learners may
   trail by more than a second at first, and sparse Vision output makes the nearest-frame lookup
   coarse.
