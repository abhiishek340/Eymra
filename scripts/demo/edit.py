"""Cuts the raw Simulator tour into a 9:16 demo: phone framed over a blurred copy of itself, serif captions,
title and end cards, music faded and loudness-matched."""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

raw, music, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out_dir, exist_ok=True)
W, H = 1080, 1920
PW, PH = 736, 1600            # the phone on the canvas (1206x2622 scaled)
PX, PY = (W - PW) // 2, 250
FPS = 60
SERIF = "/System/Library/Fonts/NewYork.ttf"
SERIF_I = "/System/Library/Fonts/NewYorkItalic.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"
GOLD = (222, 184, 120)
CREAM = (248, 242, 234)

def run(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + args, check=True)

def font(path, size):
    return ImageFont.truetype(path, size)

# --- Static art -------------------------------------------------------------------------------------
def rounded_mask(path, w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    m.save(path)

def shadow(path):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([PX + 24, PY + 24, PX + PW - 24, PY + PH - 10], 100, fill=(0, 0, 0, 150))
    img = img.filter(ImageFilter.GaussianBlur(44))
    # A dark band behind the captions, so cream type reads over light screens too.
    band = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(0, 330):
        bd.line([(0, y), (W, y)], fill=(10, 8, 7, int(205 * (1 - y / 330) ** 1.4)))
    img = Image.alpha_composite(band, img)
    ImageDraw.Draw(img).rounded_rectangle([PX - 3, PY - 3, PX + PW + 2, PY + PH + 2], 100, outline=(255, 236, 200, 70), width=3)
    img.save(path)

def caption(path, kicker, line):
    img = Image.new("RGBA", (W, 240), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = font(SANS, 30)
    spaced = "  ".join(kicker.upper())
    tw = d.textlength(spaced, font=k)
    d.text(((W - tw) / 2, 40), spaced, font=k, fill=GOLD)
    f = font(SERIF, 64)
    tw = d.textlength(line, font=f)
    d.text(((W - tw) / 2 + 2, 98), line, font=f, fill=(0, 0, 0, 120))
    d.text(((W - tw) / 2, 94), line, font=f, fill=CREAM)
    img.save(path)

def stage(draw_size=(W, H)):
    """The app's evening stage: near-black with warm light pooling at the top."""
    img = Image.new("RGB", draw_size, (14, 12, 11))
    glow = Image.new("RGB", draw_size, (0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse([W * 0.35, -500, W * 1.5, 700], fill=(150, 70, 45))
    g.ellipse([-500, H * 0.55, W * 0.6, H * 1.2], fill=(90, 70, 35))
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    return Image.blend(img, glow, 0.55)

def title_card(path):
    img = stage(); d = ImageDraw.Draw(img)
    def centred(text, f, y, fill):
        d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)
    centred("  ".join("A REAL TRIP · 50 PHOTOS"), font(SANS, 28), 700, GOLD)
    centred("Eymra", font(SERIF, 190), 760, CREAM)
    f1, f2 = font(SERIF, 70), font(SERIF_I, 70)
    a, b = "Find your ", "keepers."
    x = (W - d.textlength(a, font=f1) - d.textlength(b, font=f2)) / 2
    d.text((x, 1010), a, font=f1, fill=CREAM)
    d.text((x + d.textlength(a, font=f1), 1010), b, font=f2, fill=GOLD)
    img.save(path)

def end_card(path):
    img = stage(); d = ImageDraw.Draw(img)
    def centred(text, f, y, fill):
        d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill)
    centred("Eymra", font(SERIF, 170), 690, CREAM)
    centred("Your best moments, picked for you.", font(SERIF_I, 52), 900, GOLD)
    centred("Everything happens on your phone.", font(SANS, 34), 990, (200, 190, 175))
    small = font(SANS, 26)
    centred("Photos: Unsplash photographers, via Lorem Picsum (Unsplash License)", small, 1660, (160, 150, 138))
    centred("Music: “Inspired” by Kevin MacLeod (incompetech.com)", small, 1700, (160, 150, 138))
    centred("Licensed under Creative Commons: By Attribution 4.0", small, 1740, (160, 150, 138))
    img.save(path)

art = os.path.join(out_dir, "art"); os.makedirs(art, exist_ok=True)
rounded_mask(f"{art}/mask.png", PW, PH, 96)
shadow(f"{art}/shadow.png")
title_card(f"{art}/title.png")
end_card(f"{art}/end.png")

# --- Segments: (start, end, speed, kicker, caption) --------------------------------------------------
SEGMENTS = [
    (14.6, 23.6, 1.0, "Welcome", "Your photos, in a ring"),
    (24.0, 40.0, 1.8, "Make it yours", "Three quick questions"),
    (40.5, 49.0, 1.4, "Private by design", "It all stays on your phone"),
    (49.6, 58.0, 1.0, "Create", "Your trip, on the stage"),
    (58.0, 73.2, 1.5, "Choose", "Pick the days and the platform"),
    (73.2, 80.2, 0.85, "50 photos", "Sorted in seconds"),
    (80.2, 100.5, 1.45, "The story", "Ten keepers, in order"),
    (100.5, 106.0, 1.0, "Every pick", "says why it made the cut"),
    (106.0, 131.0, 1.7, "Stories and you", "Everything in one place"),
]

clips = []
for i, (a, b, speed, kicker, line) in enumerate(SEGMENTS):
    caption(f"{art}/cap{i}.png", kicker, line)
    dur = (b - a) / speed
    clip = os.path.join(out_dir, f"seg{i}.mp4")
    fc = (
        f"[0:v]setpts=(PTS-STARTPTS)/{speed},fps={FPS},split[a][b];"
        f"[a]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=40:2,eq=brightness=-0.42:saturation=1.2[bg];"
        f"[b]scale={PW}:{PH}:flags=lanczos,format=rgba[ph];[ph][2:v]alphamerge[phm];"
        f"[bg][1:v]overlay=0:0[bs];[bs][phm]overlay={PX}:{PY}[v1];"
        f"[3:v]format=rgba,fade=in:st=0.25:d=0.45:alpha=1,fade=out:st={max(0.8, dur - 0.7):.2f}:d=0.45:alpha=1[cap];"
        f"[v1][cap]overlay=0:12:shortest=1,format=yuv420p[v]"
    )
    run(["-ss", str(a), "-to", str(b), "-i", raw, "-loop", "1", "-i", f"{art}/shadow.png", "-loop", "1", "-i", f"{art}/mask.png",
         "-loop", "1", "-i", f"{art}/cap{i}.png", "-filter_complex", fc, "-map", "[v]", "-t", f"{dur:.3f}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-r", str(FPS), clip])
    clips.append((clip, dur))
    print(f"segment {i}: {dur:.1f}s {line}")

def card_clip(png, path, dur):
    run(["-loop", "1", "-i", png, "-filter_complex",
         f"[0:v]scale=1188:2112,zoompan=z='min(1+on/{dur * FPS}*0.06,1.06)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={int(dur * FPS)}:s={W}x{H}:fps={FPS},format=yuv420p[v]",
         "-map", "[v]", "-t", str(dur), "-c:v", "libx264", "-crf", "17", "-r", str(FPS), path])
    return (path, dur)

clips.insert(0, card_clip(f"{art}/title.png", os.path.join(out_dir, "title.mp4"), 3.2))
clips.append(card_clip(f"{art}/end.png", os.path.join(out_dir, "end.mp4"), 5.0))

# --- Join with short dissolves ---------------------------------------------------------------------
XF = 0.4
inputs, chain, offset, label = [], "", 0.0, "[0:v]"
for k, (path, dur) in enumerate(clips):
    inputs += ["-i", path]
for k in range(1, len(clips)):
    offset += clips[k - 1][1] - XF
    nxt = f"[x{k}]" if k < len(clips) - 1 else "[vout]"
    chain += f"{label}[{k}:v]xfade=transition=fade:duration={XF}:offset={offset:.3f}{nxt};"
    label = nxt
total = sum(d for _, d in clips) - XF * (len(clips) - 1)
silent = os.path.join(out_dir, "silent.mp4")
run(inputs + ["-filter_complex", chain.rstrip(";"), "-map", "[vout]", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
              "-pix_fmt", "yuv420p", "-r", str(FPS), silent])

# --- Music: fade in, fade out on the end card, loudness for social -----------------------------------
final = os.path.join(out_dir, "Eymra-demo.mp4")
run(["-i", silent, "-i", music, "-filter_complex",
     f"[1:a]atrim=0:{total:.3f},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=1.2,afade=t=out:st={total - 3.5:.3f}:d=3.5,"
     f"loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]",
     "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", "-shortest", final])
print(f"done: {final} ({total:.1f}s)")
