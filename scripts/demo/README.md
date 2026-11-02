# Demo video

Three steps, from a fresh Simulator to a 9:16 video with music.

```sh
python3 -m venv /tmp/demo-venv && /tmp/demo-venv/bin/pip install pillow piexif
/tmp/demo-venv/bin/python scripts/demo/build_trip.py /tmp/trip            # 50 photos of a two-day Lisbon trip
scripts/record-demo.sh /tmp/trip /tmp/raw.mp4                             # fresh "Eymra Demo" Simulator, records DemoTour
/tmp/demo-venv/bin/python scripts/demo/edit.py /tmp/raw.mp4 music.mp3 /tmp/edit
```

- **Photos** come from Unsplash photographers through Lorem Picsum, under the Unsplash License. `build_trip.py` gives them times over yesterday and today, places around Lisbon and Cascais, a few burst re-shoots and two weak shots (one blurry, one too dark), written into EXIF the way a phone would.
- **The tour** is `Tests/EymraUITests/DemoTour.swift`. It's skipped unless `TEST_RUNNER_EYMRA_DEMO=1`, which the record script sets.
- **The edit** cuts by time in `SEGMENTS` inside `edit.py`; after a UI change, check the timeline of the new recording and adjust the cut points.
- **Music** used for the first cut: "Inspired" by Kevin MacLeod (incompetech.com), licensed under Creative Commons: By Attribution 4.0. Keep the credit on the end card and in the post.
