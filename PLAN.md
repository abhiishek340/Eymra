# Plan

The original spec stopped at section 9, so these milestones were filled in from the earlier sections (see DECISIONS.md).

- [x] M0 – Scaffold: project.yml, scripts, CLAUDE.md, docs; app builds and launches on the Simulator
- [x] M1 – Core algorithms (segmentation, clustering, scoring, categories, selection, ordering, explanations) with unit tests
- [x] M2 – Feature extraction (Vision + Accelerate), SwiftData FeatureStore cache, fixture set
- [x] M3 – Pipeline end to end on PhotoKit; Home + progress UI; fixture end-to-end test
- [x] M4 – Results UI: reasons, best-of-N, swap, lock, hide, "Why not?"
- [x] M5 – Export: album, share sheet, Stories copy, open platform app
- [x] M6 – AI Judge (Claude) with Keychain key, cache, graceful fallback; Settings
- [x] M7 – UI smoke tests, real PhotoKit + Vision run and album export on seeded Simulator photos, README
- [ ] M7 (device) – install on an iPhone and time a 200+ photo run: blocked on a signing team (no Apple ID on this Mac)

## Identity reliability follow-up
- [x] Audit recognition, crop association, grouping, judge and selection; research model alternatives and evaluation limits
- [x] Preserve identity evidence when no user matches; prevent framing and judge labels from inventing identity
- [x] Make Me selection require a match; preserve eligible cluster members and report shortfalls
- [x] Fall back to a mix when Me can't find the user, and keep photos the user locked
- [x] Remove automatic reference expansion; preserve unreadable-face uncertainty; associate zoomed detections with their target
- [x] Allow correction of confident matches on the results screen
- [ ] Validate on the owner's actual failing photos and a held-out event split; calibrate false acceptance, coverage and final wrong-person picks
- [ ] Evaluate enrollment face choice, model/version migration and photo-specific back-view confirmation
- [ ] Benchmark alternative face models and target-aware crop quality only after the corrected baseline is measured
