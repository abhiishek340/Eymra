"""Builds a two-day Lisbon trip from Unsplash photos (via Lorem Picsum, Unsplash License):
times, places, a few burst re-shoots and two weak shots, written into EXIF like a phone would."""
import io, json, os, random, sys, urllib.request
from datetime import datetime, timedelta
from PIL import Image, ImageEnhance, ImageFilter
import piexif

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
random.seed(7)
now = datetime.now()
yesterday = (now - timedelta(days=1)).replace(second=0, microsecond=0)
today = now.replace(second=0, microsecond=0)

LISBON = (38.7139, -9.1394)
ALFAMA = (38.7118, -9.1300)
CASCAIS = (38.6979, -9.4215)
GUINCHO = (38.7290, -9.4740)

# (picsum id, portrait?, day, "HH:MM", place, bursts, note)
STORY = [
    (431, False, 0, "08:40", LISBON, 0, "latte"),
    (1060, False, 0, "08:52", LISBON, 0, "pour-over"),
    (419, False, 0, "09:30", ALFAMA, 3, "yellow trams"),
    (308, True, 0, "09:55", ALFAMA, 0, "laundry lane"),
    (322, True, 0, "10:10", ALFAMA, 0, "alley"),
    (369, False, 0, "10:30", ALFAMA, 0, "colourful houses"),
    (342, False, 0, "11:05", LISBON, 0, "market street"),
    (64, True, 0, "11:40", LISBON, 2, "portrait, sunglasses"),
    (398, True, 0, "12:10", LISBON, 0, "narrow street"),
    (292, False, 0, "13:15", LISBON, 0, "salad"),
    (488, False, 0, "13:20", LISBON, 0, "bowl"),
    (429, False, 0, "13:45", LISBON, 0, "raspberries"),
    (628, True, 0, "14:30", LISBON, 0, "camera"),
    (397, True, 0, "15:20", LISBON, 0, "hill town"),
    (49, False, 0, "16:00", LISBON, 0, "white town"),
    (1065, True, 0, "16:40", ALFAMA, 0, "alley to the sea"),
    (77, False, 0, "18:50", LISBON, 0, "pier at sunset"),
    (270, False, 0, "19:05", LISBON, 0, "old pier"),
    (195, True, 0, "21:10", ALFAMA, 0, "string lights"),
    (351, True, 0, "21:40", ALFAMA, 0, "street at night"),
    (163, False, 1, "08:45", CASCAIS, 0, "cafe with flowers"),
    (1068, True, 1, "09:00", CASCAIS, 0, "blue wall"),
    (635, False, 1, "09:15", CASCAIS, 0, "breakfast cups"),
    (493, False, 1, "09:20", CASCAIS, 0, "yoghurt"),
    (655, False, 1, "10:10", CASCAIS, 0, "camper van"),
    (211, False, 1, "10:40", CASCAIS, 0, "boats"),
    (323, False, 1, "11:30", GUINCHO, 0, "cliffs"),
    (603, False, 1, "11:45", GUINCHO, 0, "rocky coast"),
    (639, False, 1, "12:05", GUINCHO, 0, "coast from above"),
    (640, False, 1, "12:20", GUINCHO, 2, "waves"),
    (1001, True, 1, "12:50", GUINCHO, 0, "walking the beach"),
    (656, True, 1, "13:10", GUINCHO, 0, "girl on the beach"),
    (606, True, 1, "13:40", GUINCHO, 0, "boardwalk"),
    (609, False, 1, "13:55", GUINCHO, 0, "pebbles"),
    (203, False, 1, "14:30", CASCAIS, 0, "bike by the sea"),
    (665, False, 1, "15:00", CASCAIS, 0, "sitting on the cliff"),
    (372, False, 1, "15:30", CASCAIS, 0, "lifeguard hut"),
    (215, True, 1, "15:50", CASCAIS, 0, "palms"),
    (643, False, 1, "16:20", CASCAIS, 3, "surfboard at sunset"),
    (641, True, 1, "16:35", CASCAIS, 0, "lifeguard tower"),
]
WEAK = {308: "blurry", 351: "dark"}

def fetch(pid, portrait):
    w, h = (1500, 2000) if portrait else (2000, 1500)
    req = urllib.request.Request(f"https://picsum.photos/id/{pid}/{w}/{h}", headers={"User-Agent": "eymra-demo"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGB")

def gps(lat, lon):
    def dms(v):
        v = abs(v); d = int(v); m = int((v - d) * 60); s = round(((v - d) * 60 - m) * 60 * 100)
        return ((d, 1), (m, 1), (s, 100))
    return {piexif.GPSIFD.GPSLatitudeRef: b"N" if lat >= 0 else b"S", piexif.GPSIFD.GPSLatitude: dms(lat),
            piexif.GPSIFD.GPSLongitudeRef: b"E" if lon >= 0 else b"W", piexif.GPSIFD.GPSLongitude: dms(lon)}

def save(img, path, when, place):
    lat = place[0] + random.uniform(-0.002, 0.002); lon = place[1] + random.uniform(-0.002, 0.002)
    stamp = when.strftime("%Y:%m:%d %H:%M:%S").encode()
    exif = {"0th": {piexif.ImageIFD.Make: b"Apple", piexif.ImageIFD.Model: b"iPhone 17 Pro", piexif.ImageIFD.DateTime: stamp},
            "Exif": {piexif.ExifIFD.DateTimeOriginal: stamp, piexif.ExifIFD.DateTimeDigitized: stamp},
            "GPS": gps(lat, lon)}
    img.save(path, "JPEG", quality=90, exif=piexif.dump(exif))

manifest = []
for pid, portrait, day, hhmm, place, bursts, note in STORY:
    base = (yesterday if day == 0 else today)
    hh, mm = map(int, hhmm.split(":"))
    when = base.replace(hour=hh, minute=mm)
    if when > now - timedelta(minutes=5):
        when = now - timedelta(minutes=30) - timedelta(minutes=len(manifest))
    img = fetch(pid, portrait)
    shots = [img]
    # A burst: the same moment re-shot a beat later, framed a touch differently, exposure a hair off.
    for k in range(bursts):
        dx, dy = random.randint(20, 70), random.randint(10, 50)
        w, h = img.size
        crop = img.crop((dx, dy, w - (70 - dx), h - (50 - dy))).resize((w, h))
        shots.append(ImageEnhance.Brightness(crop).enhance(random.uniform(0.94, 1.04)))
    if pid in WEAK:
        shots[0] = img.filter(ImageFilter.GaussianBlur(9)) if WEAK[pid] == "blurry" else ImageEnhance.Brightness(img).enhance(0.18)
    for k, shot in enumerate(shots):
        name = f"trip-{len(manifest):02d}-{pid}{'-b' + str(k) if k else ''}.jpg"
        save(shot, os.path.join(out, name), when + timedelta(seconds=3 * k), place)
        manifest.append({"file": name, "picsum": pid, "time": (when + timedelta(seconds=3 * k)).isoformat(), "note": note})
    print(f"{pid:5d} {when:%a %H:%M} {note} ({len(shots)} shot{'s' if len(shots) > 1 else ''})")

json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
print(len(manifest), "photos")
