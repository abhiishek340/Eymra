# Eymra

Eymra turns a pile of trip or event photos into the 5–20 worth posting: the best shot of every moment, no repeated backgrounds, a mix of kinds of shots, and a reason for every pick. Analysis runs on the iPhone with Apple Vision. An optional AI Judge sends small thumbnails with all metadata stripped to Claude, using your own API key.

## Setup
1. Xcode 26 or 27, plus `brew install xcodegen xcbeautify`.
2. `scripts/gen.sh` creates `Config/Secrets.xcconfig` (git-ignored) and generates `Eymra.xcodeproj`. Never edit the project by hand; edit `project.yml`.
3. Simulator: `scripts/run-sim.sh` runs against the Simulator's photo library. `scripts/run-sim.sh -uiTesting` runs on the bundled 40-photo fixture set. To put the fixtures into the Simulator's Photos app (dated 24 Oct 2026), run `scripts/seed-sim-photos.sh`.
4. Tests: `scripts/test.sh` runs all unit tests and the UI smoke tests. To run the real-library test (PhotoKit, Vision and album export) against the seeded Simulator: `TEST_RUNNER_EYMRA_REAL_LIBRARY=1 scripts/test.sh -only-testing:EymraUITests/RealLibraryTest`.

## Running on an iPhone
1. In Xcode → Settings → Accounts, add your Apple ID (a free one works). Then run `security find-identity -v -p codesigning` and copy the 10-character team ID.
2. Put `DEVELOPMENT_TEAM = XXXXXXXXXX` in `Config/Secrets.xcconfig`. If that bundle ID is taken, change `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
3. On the phone: Settings → Privacy & Security → Developer Mode → on. Connect it to the Mac, unlock it and tap Trust.
4. Run `scripts/build-device.sh && scripts/install-device.sh`. The first time, trust the developer app in Settings → General → VPN & Device Management. With a free Apple ID the install stops launching after 7 days; re-run the same command.

## Claude's help (your Claude API key)
In the app: **You** tab → **Claude's help** → switch on → paste your key (from console.anthropic.com → API keys) → **Save key**. The key is stored in the phone's Keychain; it is never in the code or the repo. Choose Balanced (Sonnet 5.5, about 15¢ a go), Fast and cheap (Haiku 5.5, about 1¢) or Best quality (Opus 5.5, about 30¢). Without a key, offline, or on any error, the app uses the on-device picks and says why.

## Sign in with Google
1. In Google Cloud Console → APIs & Services: set up the OAuth consent screen (External, Testing, add your Gmail as a test user).
2. Credentials → Create credentials → OAuth client ID → **iOS**, bundle ID `app.eymra.Eymra`.
3. Copy the client ID (ends in `.apps.googleusercontent.com`) into `Config/Secrets.xcconfig` as `GOOGLE_CLIENT_ID = …`, then rebuild.
Until then, the sign-in step asks for a first name instead.

## Your face
Onboarding (or **You → Your face**) scans your face from five angles with the front camera, or uses 3–6 photos you choose. It is used only to tell your photos from your friends' and stays on the phone. The Simulator has no camera and can't make face prints, so recognition only works on a real iPhone.

## Tuning
Every threshold and weight is in `Sources/Eymra/Core/Tuning.swift`. The ones most worth adjusting after a real trip:
- `duplicateDistance` (0.5): raise it to merge more shots into one moment, lower it to split them.
- `sameBackgroundDistance` (0.75): lower it to allow two picks with similar backdrops.
- `sceneDistanceMeters` (400) and `sceneMinGap`/`sceneMaxGap`: control when one place ends and the next begins.
- `mmrLambda` (0.7): lower it for more variety, raise it for pure quality.
- `sceneCapShare` and `categoryCapShare`: the most one place or one kind of shot can take of the set.
- The scoring weights `weightsWithFaces` and `weightsNoFaces`, and `judgeWeight` (0.5).

Record any change in `DECISIONS.md`. If you change what feature extraction stores, bump `FeatureSchema.version` in `Core/Models.swift`.

## Notes
- On the Simulator, Vision can't build several of its models, so there are no faces, labels or feature prints: categories show as "Other", and near-duplicates are matched by thumbnail similarity instead. The full analysis needs a real iPhone.
- Nothing leaves the phone unless the AI Judge is on. There are no accounts, servers or analytics.
