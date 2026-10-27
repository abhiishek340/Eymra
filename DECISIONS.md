# Decisions and deviations from SPEC

Each entry: what the spec said, what was done, why.

## Environment and naming
- **App name.** Spec: Keepers. Built as **Eymra** (owner's request): targets `Eymra`, `EymraTests`, `EymraUITests`; bundle ID `app.eymra.Eymra`; logger subsystem `app.eymra`; album titles start "Eymra –".
- **Toolchain.** Xcode 27.1 on macOS 27.0.1, iOS 27.1 SDK, Simulator `iPhone 18 Pro` (iOS 27.0). Deployment target iOS 18.0 as specified.
- **Simulator viewer.** Xcode 27 ships `DeviceHub.app` instead of `Simulator.app`; `scripts/run-sim.sh` opens whichever exists (simctl works headless either way).
- **Signing.** No Apple ID / team was available (`security find-identity` shows 0 identities), so device install (M7 device step) is deferred. `DEVELOPMENT_TEAM` goes in `Config/Secrets.xcconfig`; scripts are ready.
- **Spec stopped early.** The original spec ended in §9 ("Plumbing"). Sections 10–14 (platform presets, UI details, export, commands, milestones, tuning list) were reconstructed from the earlier sections; see below.

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

## Device
- Signing uses a free Personal Team set in `Config/Secrets.xcconfig` (git-ignored). First device: an iPhone 17 Pro on iOS 26.7.1.
- `UIRequiresFullScreen = YES` added: portrait-only apps must declare it, or Xcode warns that all orientations must be supported.
- Device scripts locate the phone by `devicectl` "physical" rows (the Simulator also shows as "connected") and build for its exact ID so a free team can create the provisioning profile.

## Round 2: profile, face, story, glass redesign (2026-10-25)
- **Sign in with Google without Google's SDK.** `ASWebAuthenticationSession` + OAuth 2.0 PKCE (Google's installed-app flow; iOS OAuth clients have no secret), reading only the ID token's basic profile. No server, so the "account" is a profile kept on the phone. Needs `GOOGLE_CLIENT_ID` (an iOS OAuth client for `app.eymra.Eymra`) in `Config/Secrets.xcconfig`; until then the sign-in step asks for a first name instead. Sign in with Apple was not used: a free Personal Team can't enable that capability.
- **Recognising the user.** iOS has no public face-recognition model, and v1 bundles no ML models, so the user is recognised by comparing Vision feature prints of face crops (`FaceEmbedder`) with reference prints from a guided camera scan (straight, left, right, up, down; auto-captured when Vision's yaw/pitch match and the head is held 0.4 s) or 3–6 chosen photos. The match threshold adapts to the spread of the user's own references (`Identity.threshold`, ×1.25, clamped 0.45–0.95) and is marked needsCalibration. Face data is stored in Application Support, excluded from backups, never sent to Claude.
- **When the face is set up but never found in a run**, everyone is treated the same (no "friends" category) and the results say so, instead of calling every face "friends".
- **New category `friends`**: people in the photo, but not the user. Claude can't know who the user is, so its category never overrides "friends".
- **Preferences from onboarding** (`UserPrefs`): what you post (mostly me / with friends / everything / places), group photos (love / sometimes / not really), order (story / best first). They set the default Mix, a target share of "you" photos (60 / 50 / 40 / 20 %), penalties for friends-only photos, and a bonus or penalty for group shots with you.
- **Story-aware selection and order** (after Obrador et al. 2010 on audience-dependent summarisation, and the "acts and scenes" idea): a coverage bonus for the first pick from each place, scaled by √(photos taken there); a story order with an opener (a strong photo of you), the day in time order with a rhythm pass that avoids two shots of the same kind back to back within a place, and a closer (strong, wide and late in the day). Picks carry `role` (opener/closer).
- **Face quality** weights the user's own face most: the user blinking costs ×0.3, a friend blinking ×0.6.
- **Story title**: Claude writes a 3–6 word title when its help is on (one extra small call; failure keeps the simple title); otherwise "Your Saturday" / "Your 3 days, 4 places", counted in calendar days of the photos themselves.
- **Feature schema v2** (face prints). Old caches are re-analysed once.
- **Design**: a slowly moving `MeshGradient` sky with drifting light, Liquid Glass (`glassEffect`, iOS 26) for every card, chip and button with a frosted-material fallback on iOS 18–25, serif (New York) headlines, a custom floating glass tab bar (Create, Stories, You), and frosted fades under floating controls. The reference image was used for mood only.
- **Plain language** throughout: "Claude's help" instead of "AI Judge", "almost-same shots", "Same spot as photo 5", "Good, but it came #12 and just missed out".

## Round 3: real face recognition (2026-10-25)
- **Problem found:** round 2 recognised the user with Vision's generic image feature print on face crops. That print describes overall appearance (light, colour, angle), not identity, and the threshold was set from the spread of the user's own five head angles, which is large, so it hit its loosest value (0.95) and almost any face matched.
- **Fix:** bundle a real face-recognition model, OpenCV Zoo's **SFace** (Apache-2.0), converted to Core ML (18 MB, float16; see `ThirdParty/README.md`). This deviates from the spec's "no bundled models in v1", because without it the feature the owner asked for can't work.
- Faces are aligned with a 5-point least-squares similarity transform (eyes, nose, mouth corners from Vision `DetectFaceLandmarksRequest`) to the 112×112 ArcFace template, then embedded and L2-normalised. Matching is cosine similarity ≥ 0.40 (`Tuning.meSimilarity`).
- **Measured.** Python reference on 1,000 LFW pairs: 98.8 % with landmark alignment versus 85–89 % with box crops (up to 17 % false matches), so faces without landmarks, or narrower than 40 px, get no signature ("can't tell" rather than a guess). The app's Swift path on 200 LFW pairs: 98.5 % with 0 false matches on the Simulator, and on the iPhone 17 Pro with Vision landmarks end to end, 97.5 % with 0 false matches. The test images are local only (`Tests/LocalFaces`, git-ignored); `FaceRecognitionTests` skips the real-face checks when they're absent.
- **Face setup** now drops captures that don't agree with the rest (`Identity.consistentReferences`, cosine ≥ 0.35 to the best-supported capture), so someone else in the frame or in a chosen photo doesn't become "you".
- On the Simulator the model runs CPU-only (the GPU/ANE path fails there); on device it uses all compute units and falls back to CPU if a prediction fails. Feature schema 3: caches are re-analysed once.

## Round 3: motion, glitches and "magic" (2026-10-25)
- **Causes of the glitches found:** (1) every screen and sheet drew its own animated sky, with three large blur filters re-rendered 30 times a second; (2) finishing a run dismissed a full-screen cover and pushed a navigation screen at the same moment, so two skies slid over each other; (3) tabs were rebuilt on every switch; (4) a tab-bar transition ran during the push.
- **Fixes:** one `DreamBackground` at the root for the whole app (radial-gradient light, no blur filters, `drawingGroup`, 24 fps, paused when inactive or with Reduce Motion; sheets use material, the photo detail a static sky). Create is one screen with three states (setup → working → story) using blur-replace transitions; no covers or pushes. Tabs stay alive and cross-fade. The photo detail opens with a zoom transition from its card.
- **Working state:** the user's own photos orbit a breathing light on a tilted ring (stable per-photo angles, so arrivals never make others jump); a thin ring shows overall progress; the picks gather into a fanned hand before the story blooms in (1.4 s). The pipeline now sends a spread of photo IDs at ingest, each photo as it's analysed, and the final order.
- **Motion language:** text writes itself in (a `TextRenderer` fading and un-blurring glyphs in turn), cards rise in with staggered springs, scroll transitions, a slight photo parallax, pressable cards, and haptics on tab changes, stage changes and the reveal.
- **No machinery on screen:** no "Claude", "AI", "on-device" or stage jargon on any screen. Claude's help is called "Deeper picks" (it still needs the user's Anthropic key), the speed options are Balanced / Fast / Most careful, and a key or credit problem shows only in the You tab. No sparkle or wand icons: plain SF Symbols (photo.stack, book.closed, person.crop.circle, arrow.right).
- **UI tests:** the working state animates constantly (and lasts about 2 s with 40 fixtures), so the test photographs it instead of querying it. Its caption is one accessibility element with the current line.

## Round 4: every way back, end-to-end tests, calmer colours (2026-10-25)
- **Back navigation.** Removing the navigation stack in round 3 also removed the system swipe-back gesture. The story screen now has an edge swipe that follows the finger, onboarding has a back button on every step, Create shows "Your last story" to reopen it, and the photo view closes with a pull-down as well as Done.
- **Glass buttons and taps.** On iOS 26 an interactive glass effect inside a Button's label can take the touch for itself, so the button never fires. Glass is now non-interactive by default; buttons do their own press animation.
- **Small fixes found by testing:** "Copied" messages showed behind the photo view (the photo view now shows its own); the "Open Instagram" button had no label; Stop stays disabled while the picks gather; the key field saves on Done (the Save button sits under the keyboard); a refused Keychain write now says so.
- **End-to-end UI tests** (`EndToEndTests`) cover onboarding forward and back, every setup control, every way back from the story, Stop while working, the photo view (keep, copy, pull to close, runner-up), hiding, other photos and why-not, pick again and share, the You tab (style, key, face photos, hidden photos, sign out) and tab state. They run with `-stillMotion`, which pauses the endless decorative motion (as Reduce Motion does) so the test runner can settle between taps, and `-noGoogle` where the name-only path is under test. UI tests keep the Anthropic key in memory, because unsigned Simulator builds can't write to the Keychain.
- **Colours.** No purple anywhere. The sky follows the time of day (morning cream, clear pale midday, warm golden evening, deep night in dark mode), low-saturation so glass and text stay calm, following guidance that glass reads best over soft neutrals with high-contrast text, and Tide Guide's time-of-day palette (Apple Design Award 2026). The main action is a solid ink pill; selected chips and the tab pill fill with ink. The app icon is a sky-to-meadow gradient with white photo cards and a warm sun.
- **Motion presets.** `Theme.Motion.snap / pop / settle` springs and matching haptics on presses, so every interaction feels like the same app.

## Round 5: show, don't tell (2026-10-25)
- **Feedback:** every screen was heading, sentence, card, repeated. The screens now show things instead of explaining them.
- **Create:** your own photos from the chosen time fanned out with a big count; a bar chart of photos per day for the last week (tap a day to pick it); platforms as tiles showing the real shape of the post; a row of dots for how many photos (tap one to set the count); and a three-way icon switch from "Me" to "Places". Section headings are single small words.
- **Story:** a glance strip ("40 → 10", places, photos of you), the day as a timeline with a dot per place and the picks floating above it, and a colour bar for the mix of shots. Cards use a coloured icon for the kind of shot and a stacked-cards icon for "best of N".
- **Photo view:** four animated score rings (Sharp, Looks, Framing, Faces) instead of rows of bars.
- **Stories:** each past story is a photo mosaic with the title over the image.
- **Onboarding:** a drawn illustration of photos floating up (nothing bundled), answers as a 2×2 grid of big icon tiles, and the face intro as a face with five orbiting dots (one per scan angle) and three icon chips.
- **Night colours:** light mode now stays light at night (a pale moonlit mist). The deep night sky is for dark mode only; before, dark ink text sat on a dark sky after 9 pm.
- Category colours are muted and purple-free (slate, blue-grey, teal, soft blue, sage, sand, taupe).

## Round 6: the Paper theme (2026-10-25)
- **Feedback:** the app looked basic, and the dark blue was unwanted; the ask was to be as clean as Hinge or Uber and as creative.
- **Paper theme:** a flat warm off-white page (warm charcoal in dark mode, never blue), solid surface cards with a hairline and a soft shadow, near-black type, and one accent, ember orange, used only for the count sticker, the opener label and progress. The moving gradient sky is gone, which also removes its per-frame cost. Glass stays only for the floating tab bar and floating buttons.
- **Creative touches:** an editorial serif headline ("Find your *keepers*.") with the one italic word in ember; the user's photos as a scrapbook of tilted, white-bordered prints with a round dashed-edge "40 photos" sticker; story cards with a white number badge and an ember "Opens your story" label.
- Chips and secondary buttons are solid pills with a hairline instead of glass, which reads crisper on paper.
- **Grouping fix (round 5b):** near-duplicates now need the same people (face signature similarity ≥ 0.32 for solo and pair shots), so a friend posing at the same spot is not another take of you, and the runner-up strip never mixes a photo of you with one that isn't.

## Round 7: find the face, then zoom in (2026-10-25)
- **What recognises you:** Apple Vision finds faces and their eyes, nose and mouth; the face is aligned to a 112×112 template; OpenCV Zoo's SFace model (Apache-2.0, on device through Core ML) makes a 128-number signature; cosine similarity ≥ 0.40 against your profile counts as you. Claude is never involved and never sees a face.
- **Problem:** faces were found and read on a 1024 px copy of each photo, and anything under 40 px there was skipped, so you in group and scenic shots was never recognised. Vision also often can't place landmarks on such small faces.
- **Fix (the owner's tip):** find faces on the small copy; for any face under 160 px there, fetch a 3072 px copy, crop a square 2.2× the face, enlarge it to at least 400 px, re-detect the face in the crop, find its landmarks, then embed. The minimum readable face is now 24 px in the sharper copy.
- **Mirror trick:** each face is embedded as it is and mirrored, and the two are averaged.
- **Run references:** faces in a run that match your profile at ≥ 0.55 join your references for that run (up to 24), so a shot of you looking down can match a clear shot from the same day. Only matches to the profile itself are added, so it can't drift through look-alikes.
- **Measured on the iPhone 17 Pro:** full chain on 200 LFW pairs 98.5 % (was 97.5 %), 0 false matches. Faces shrunk to about 25 to 30 px in a wide frame: all 100 read, 97 % correct, 0 false matches (before, all skipped). Python reference: 30 px faces 97.9 %, 20 px faces 95.4 %.
- **Models considered:** stronger models (InsightFace ArcFace weights, EdgeFace, GhostFaceNets) carry non-commercial or negotiated licences, and the one ready-made Swift ArcFace package is a paid service. SFace stays, as it's accurate and can ship commercially.
- Feature schema 4 (faces are re-read once). Saved face scans are re-made automatically from the stored face crops (`MeReference.version`), so no rescan is needed.

## Round 8: sure, unsure and not you (2026-10-26)
- **Feedback:** photos of someone else were still shown as you.
- **Two causes, neither of them the model.** First, the deeper picks step labels a photo "me" whenever one person fills the frame, because it can't know who the user is, and that label overwrote what face recognition said. Second, the saved face scan was three sideways, very close crops (one blurry). Read sideways, they matched each other at only 0.31 to 0.57; turned upright, 0.54 to 0.63.
- **Who is in a photo now comes from face recognition only.** Once a face is set up, the deeper picks step can't change a people category in either direction. A photo with people where your face isn't recognised either way is "Someone", never "You".
- **Three answers, not two.** At 0.50 or more a face is you; under 0.38 it isn't; in between, Eymra asks "Is this you?" with the face cut out of the photo. Answers are saved with the face scan and used in every later run (a "not me" answer wins when it's the closer match).
- **A better face scan.** Every capture is turned upright first (quarter turns until the head roll is under 30°), checked with Vision's face capture quality, and rejected if the face fills more than 62% of the width or doesn't match the earlier captures at 0.45 or more. The scan says why ("a bit closer than needed", "too blurry").
- "More of me" now only favours photos that are really you, not photos of other people.
- UI tests keep the face scan in a temporary folder, so running them on a phone never touches the owner's real scan.

## Round 9: who is in the photo comes first (2026-10-26)
- **A bug round 8 missed.** When no photo in a run matched your face for sure, the pipeline threw your face profile away and scored the run again without it. That brought back "a big face means you", so close-ups of friends were called You. The profile now stays, whatever happens.
- **Framing never decides who it is.** Without a face scan, a photo with people in it is "Someone", not You or a group of you and friends. The deeper picks step can't add a people label either.
- **Me means only photos of you.** The Me option (now called "Only photos of me") only picks photos where your face matched for sure. It never fills the count with other people; it shows fewer photos and says why. Two exceptions:
  - If you aren't found at all, or there's no face scan yet, Me falls back to a mix and says so, so you never get an empty story.
  - A photo you locked or swapped in yourself stays, even if it isn't you.
- **No chained matches.** Faces that matched during a run no longer join your references. One wrong match used to become evidence for more. Only the face scan and your own "Is this you?" answers count.
- **Unknown stays unknown.** A photo with one readable friend and one unreadable face isn't "not you". Broken or empty face signatures are never compared.
- **Reading the right face after zooming in.** The zoomed crop keeps where the original face was. The app only reads a face that overlaps it (IoU 0.3 or more), and skips the photo if two faces do. Before, it took whichever face was nearest the centre, which could be the person next to you. Feature schema 5, so faces are read again once.
- **Fixing confident mistakes.** "Check who is in these photos" lists every matched face, not just the unsure ones, so a wrong match can be marked Not me.
- **Still to do.** The 0.50 and 0.38 thresholds came from LFW pairs, not real camera rolls. They need checking on real trips with look-alike friends before claiming any accuracy number. `reports/` has a research note suggesting EdgeFace and AuraFace may have licences that allow shipping. Worth a benchmark once the licence of the exact weights is confirmed.

## Round 10: motion with a purpose (2026-10-27)
- **Welcome.** A warm gradient of paper, peach and soft ember drifts slowly behind the page (a 3×3 mesh, 30 fps, welcome and the working screen only). Five drawn prints are dealt out of a pile, one after another, then float. The main button catches a streak of light every few seconds.
- **Onboarding fixes.** The question progress moved next to the back button (it was hidden under it) and grows from one question to the next. The keyboard closes after the name, which was squeezing the first question's title into one cut-off line. Titles now always wrap. A picked answer gets a small ember tick and a pop.
- **Create.** Your photos are dealt into the scrapbook and the count sticker stamps on with a soft tap. Tap the scrapbook to shuffle it. The Focus switch has one pill that slides between options, and the day chart's bars grow up when the screen opens.
- **Story.** The 40 → 10 numbers roll up, your picks drop onto the day line one by one, the mix bar fills colour by colour, and "Check who is in these photos" is a proper chip.
- **Rules kept.** Every endless motion stops under Reduce Motion and in UI tests (`-stillMotion`); one-off entrances still run. Pops only play on the item being selected, not the one being let go of.
- **A lesson.** The first version of the light streak was an offset overlay outside the button. It stretched the button's frame to 745 pt, so a tap at its centre missed, and it duplicated the button's test ID. The streak now lives inside the button style as a moving gradient, so it can never change where the button is.
