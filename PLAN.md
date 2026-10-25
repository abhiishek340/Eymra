# Plan

The pasted spec ended in §9, so the milestones below are reconstructed (see DECISIONS.md).

- [x] M0 – Scaffold: project.yml, scripts, CLAUDE.md, docs; app builds and launches on the Simulator
- [x] M1 – Core algorithms (segmentation, clustering, scoring, categories, selection, ordering, explanations) with unit tests
- [x] M2 – Feature extraction (Vision + Accelerate), SwiftData FeatureStore cache, fixture set
- [x] M3 – Pipeline end to end on PhotoKit; Home + progress UI; fixture end-to-end test
- [x] M4 – Results UI: reasons, best-of-N, swap, lock, hide, "Why not?"
- [x] M5 – Export: album, share sheet, Stories copy, open platform app
- [x] M6 – AI Judge (Claude) with Keychain key, cache, graceful fallback; Settings
- [x] M7 – UI smoke tests, real PhotoKit + Vision run and album export on seeded Simulator photos, README
- [ ] M7 (device) – install on an iPhone and time a 200+ photo run: blocked on a signing team (no Apple ID on this Mac)
