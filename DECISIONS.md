# Decisions and deviations from SPEC

Each entry: what the spec said, what was done, why.

## Environment and naming
- **App name.** Spec: Keepers. Built as **Eymra** (owner's request): targets `Eymra`, `EymraTests`, `EymraUITests`; bundle ID `app.eymra.Eymra`; logger subsystem `app.eymra`; album titles start "Eymra –".
- **Toolchain.** Xcode 27.1 on macOS 27.0.1, iOS 27.1 SDK, Simulator `iPhone 18 Pro` (iOS 27.0). Deployment target iOS 18.0 as specified.
- **Simulator viewer.** Xcode 27 ships `DeviceHub.app` instead of `Simulator.app`; `scripts/run-sim.sh` opens whichever exists (simctl works headless either way).
- **Signing.** No Apple ID / team was available (`security find-identity` shows 0 identities), so device install (M7 device step) is deferred. `DEVELOPMENT_TEAM` goes in `Config/Secrets.xcconfig`; scripts are ready.
- **Spec truncated.** The pasted spec ended in §9 ("Plumbing"). Sections 10–14 (platform presets, UI details, export, commands, milestones, tuning list) were reconstructed from the earlier sections; see below.

## Reconstructed sections (10–14)
- **Platform presets** (`Core/PlatformPreset.swift`): Instagram carousel 10/20, 4:5 then 1:1, cover-then-story order; Instagram post 1/1, 4:5; Reels/TikTok 10/20, 9:16, chronological; Facebook 6/20, 4:5/1:1/1.91:1, cover-then-story; X 4/4, 16:9, best first.
- **Ordering** (`Core/Ordering.swift`): cover = best people shot (else best shot), closer = best of the rest, middle in capture order.
- **Selection constraints**: scene cap = max(2, ⌈0.34·N⌉), category quota = max(2, ⌈0.4·N⌉), same background = feature-print distance < 0.75 between winners of different clusters. When the count can't be met they relax in order category quota → scene cap → same background, and the results screen lists each relaxation.
- **R with judge**: R = 0.5·Q + 0.5·J (`Tuning.judgeWeight`).
- **Limited-access warning**: banner on Home with a link to Settings.
- **Milestones**: M0 scaffold, M1 core + tests, M2 features + cache, M3 pipeline + Home/progress, M4 results UI, M5 export, M6 AI Judge + Settings, M7 UI test + real-Vision Simulator run + README + device.

## API substitutions (SDK reality)
- `PHAssetMediaSubtype.photoAnimation` does not exist; animated images are detected with `asset.playbackStyle == .imageAnimated`.
- `GenerateImageFeaturePrintRequest.Revision` has only `.revision2` in the iOS 27.1 Swift API; revision is stored as 2 (3 for anything else).
- Face capture quality: `FaceObservation.captureQuality?.score`.
- `vDSP.convolve(_:rowCount:columnCount:with3x3Kernel:result:)` used as specified; the 1-pixel border is excluded from the variance.
- Saliency/face/human rects are converted from Vision's lower-left origin to upper-left.

## Model and data deviations
- `RunResult` also stores `scores: [String: PhotoScore]` so the swap UI and "Why not?" can show runner-up scores without re-running.
- `PhotoRecord` has an extra `isAnimated` flag (from `playbackStyle`).
- `JudgeScore.category` is optional: a provider that gives no category keeps the heuristic one (used by `StubJudge`).
- `RunStats.judgeNote` added: the user-facing reason the judge was skipped or failed.
- Stage 6 orchestration lives in `Pipeline/JudgeStage.swift` (not listed in the spec layout).
- `StageTimer` replaces closure-wrapped timing because Swift 6 region isolation rejects mutating `stats` from a closure.

## AI Judge
- Request: `anthropic-version: 2023-06-01` as the spec says (the newer 2026-10-21 version only removes sampling parameters, which this client never sends). `output_config: {effort: "low", format: {type: "json_schema", schema}}` keeps the per-image rubric call fast.
- Refusals (`stop_reason: "refusal"`) are treated like any other judge error: on-device picks stand and the UI says so. No server-side fallback models are configured, to keep the call to the model the user chose.
- Model list and cost estimates follow the spec (Sonnet 5.5 default ≈ $0.15, Haiku 5.5 ≈ $0.01, Opus 5.5 ≈ $0.30 per 60-photo run).

## Fixtures
- `scripts/make-fixtures.swift` draws 40 synthetic JPEGs (900×1200 / 1200×900, EXIF date + GPS) across 5 scenes and writes `features.json` with synthetic 32-dim unit feature vectors, so pipeline tests are deterministic on the Simulator (where real feature prints are unreliable).
- Lake poses: moment spread raised 0.35 → 0.5 so the two poses are distinct moments (distance ≈ 0.63 > 0.5) that still share a background (< 0.75).
- `-uiTesting` rebases fixture dates so the newest is one hour ago and defaults the range to "Last 3 days".

## Vision on the Simulator
- Spec: if the packed core Vision request throws, exclude the photo as *Could not analyse*. On the iOS 27 Simulator the pack throws `internalError("Could not create inference context")` for every photo, which would exclude everything. Now a failed pack retries each core request on its own (`try?`); only a decode or image-statistics failure excludes the photo. A missing feature print falls back to the spec's thumb32 RMS rule in clustering, and same-background checks are skipped for that photo.
- Tests: `-collect-test-diagnostics never` in `scripts/test.sh`, otherwise any failure triggers a 10-minute `simctl diagnose`.
