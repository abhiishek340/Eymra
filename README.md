# Eymra

You come back from a trip with 400 photos and want to post ten. Eymra goes through them for you and hands back the few worth sharing: the best shot of every moment, no near duplicates, no two photos from the same spot, and a good mix of you, your friends, the views and the food. It puts them in an order that tells the story of the day.

It's a native iPhone app written in Swift and SwiftUI. All the photo analysis happens on the phone.

## What it does

- **Pick a time and a place to post.** Today, yesterday, the last few days or a custom range, then Instagram, Reels and TikTok, Facebook or X. Each platform gets its own photo count and crop shape.
- **Finds you in your photos.** A quick face scan (or a few photos of yourself) lets Eymra tell your photos apart from your friends' photos.
- **Learns your style.** Three questions during onboarding: do you mostly post yourself, how do you feel about group photos, and should the post read like a story or lead with the best shot.
- **Explains itself.** Every pick says why it was chosen ("the sharpest of 8 almost-same shots"). Every photo that didn't make it says why not ("same spot as photo 5"), and you can swap it in with one tap.
- **Lets you take control.** Lock the photos you love and pick again, swap in a runner up, or hide a photo for good.
- **Exports cleanly.** Save the set to an album in order, share it, or copy a single photo cropped for your Story.
- **Deeper picks (optional).** With your own Anthropic API key, Eymra takes a closer look at the shortlist and writes a title for the set. Without a key, or offline, it simply skips this step.

## How the picking works

1. **Moments and places.** Photos are grouped into scenes by time gaps and by distance travelled, then into moments: shots of the same thing taken seconds apart.
2. **Best of each moment.** Each photo gets a score for sharpness and exposure, a general "does this look good" score from Apple's Vision framework, framing, and faces (eyes open, smiles, and your face counts most). The top photo in each moment wins.
3. **A set, not a list.** Picks are chosen one at a time, balancing quality against variety. Repeated backgrounds are blocked, no single place or kind of photo can take over, and every place you went gets a fair chance.
4. **Story order.** It opens with a strong photo of you, follows the day in time order without two similar shots back to back, and closes on a good moment from late in the day.

Faces are recognised with the SFace model from OpenCV, running on device through Core ML. Each face is lined up by its eyes, nose and mouth before comparing. On real face pairs that's about 97 to 98% accurate, with no false matches in our tests. A face that's too small to read is treated as unknown, not guessed.

## Privacy

- Photos are analysed on the phone. There's no Eymra server, no account system, no analytics and no ads.
- Your face setup never leaves the phone and isn't included in backups.
- Deeper picks is off by default. When you turn it on, small copies of the shortlisted photos go to Anthropic using your own key, with location and all other metadata stripped first.

## Requirements

- A Mac with Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and optionally [xcbeautify](https://github.com/cpisciotta/xcbeautify): `brew install xcodegen xcbeautify`
- iOS 18 or newer. Liquid Glass shows on iOS 26; older versions get a frosted glass look instead.

## Getting started

```sh
git clone https://github.com/abhiishek340/Eymra.git
cd Eymra
scripts/run-sim.sh -uiTesting
```

The project file is generated, so there's no `.xcodeproj` in the repo. `scripts/gen.sh` creates it from `project.yml` and copies `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` the first time.

`-uiTesting` runs the app on a bundled set of 40 test photos, so you can try everything without a photo library. To use the simulator's real Photos app instead, load the same test photos into it and run without the flag:

```sh
scripts/seed-sim-photos.sh
scripts/run-sim.sh
```

The test photos are dated 24 October 2026, so pick that day as a custom range.

The simulator can't run Vision's face models, so face detection and recognition only really work on a phone.

## Running on your iPhone

1. In Xcode, open Settings, then Accounts, and add your Apple ID. A free account is fine.
2. Run `security find-identity -v -p codesigning` and put your 10 character team ID in `Config/Secrets.xcconfig` as `DEVELOPMENT_TEAM = XXXXXXXXXX`.
3. On the phone, turn on Developer Mode (Settings, Privacy & Security), then plug it in, unlock it and tap Trust.
4. Run `scripts/build-device.sh && scripts/install-device.sh`.
5. The first time, trust the developer app on the phone under Settings, General, VPN & Device Management.

With a free Apple ID the app stops opening after 7 days. Run step 4 again to reinstall.

## Optional setup

**Deeper picks.** In the app, open the You tab, turn on Deeper picks and paste your Anthropic API key (get one at [console.anthropic.com](https://console.anthropic.com)). The key is stored in the phone's Keychain, never in the code.

**Sign in with Google.** Create an iOS OAuth client in the Google Cloud Console for the bundle ID `app.eymra.Eymra`, then add it to `Config/Secrets.xcconfig` as `GOOGLE_CLIENT_ID = ....apps.googleusercontent.com`. Until it's set, onboarding just asks for your first name.

## Project layout

```
Sources/Eymra/
  Core/        Pure Swift logic: scenes, duplicates, scoring, faces, selection, story order. All thresholds live in Tuning.swift.
  Pipeline/    The pipeline that runs every step, plus the optional deeper picks step.
  Services/    Photos, Vision, the face model, the on-device cache, export and the Anthropic client.
  App/         App state, account, settings.
  UI/          SwiftUI screens and the glass design system.
Tests/         Unit tests (Swift Testing) and UI tests (XCTest).
Fixtures/      40 generated test photos with matching feature data.
scripts/       Build, test, run and install helpers.
ThirdParty/    Licence and conversion notes for the face model.
```

`DECISIONS.md` explains the bigger design choices and why they were made.

## Tests

```sh
scripts/test.sh                                         # everything
scripts/test.sh -only-testing:EymraTests/SelectionTests # one suite
```

About 100 unit tests cover the picking logic, the cache, face matching and the full pipeline on the test photos. The UI tests walk through onboarding, a full run, editing the picks and every tab.

## Tuning

Every number the picking uses is in `Sources/Eymra/Core/Tuning.swift`. The ones worth playing with after a real trip:

- `duplicateDistance`: higher merges more shots into one moment.
- `sameBackgroundDistance`: lower allows two photos from similar spots.
- `sceneDistanceMeters`, `sceneMinGap`, `sceneMaxGap`: when one place ends and the next begins.
- `mmrLambda`: lower means more variety, higher means pure quality.
- `meSimilarity`: how sure the app has to be that a face is yours.

## Credits

- Face recognition: [SFace](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) from OpenCV Zoo, Apache 2.0. See `ThirdParty/`.
- Scene splitting follows PhotoTOC (Platt, Microsoft Research, 2002). Choosing a varied set uses Maximal Marginal Relevance (Carbonell and Goldstein, 1998). Story order and coverage take ideas from work on audience dependent photo summarisation (Obrador et al., ACM Multimedia 2010).
