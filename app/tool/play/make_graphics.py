"""Google Play phone screenshots (1080x1920) + feature graphic (1024x500) from real emulator captures, in the design
system of the owner's PDF NOVA listing (docs/play/SCREENSHOTS.md), in Earmark's palette.
Usage (from app/): python tool/play/make_graphics.py build/store/raw ../dist/play-store-assets
  raw/<theme>-<scene>.png  captures from integration_test/store_tour_test.dart (1080x2400, light and dark system theme)
  -> screenshots/en/NN_<key>.png, feature-graphic/feature_graphic_en.png, previews/contact_sheet_en.png,
     source/en/*.html (the page each PNG was rendered from), logo/icon_play_512.png
Pages are HTML rendered by headless Chrome at 2x, then downsampled. The phone screens are the real captures; only the
system status and navigation bars are replaced by a neutral bar."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
APP = Path(__file__).resolve().parents[2]
REPO = APP.parent
FONT = APP / "assets/fonts/MonaSans-Variable.ttf"
BRAND = REPO / "docs/brand"
# Rows where the status bar ends / the gesture bar starts on the Shared_API35 emulator (1080x2400).
BARS = (100, 2337)  # status bar 0-74 (dumpsys window); app content starts at 123

# key: headline ([...] = highlighted), supporting line. Order = order on the listing.
COPY = {
    "home": ("Mark the moments [that matter]", "Tap anywhere while you record. Jump straight back later."),
    "live": ("One tap. [Bookmarked.]", "Half the screen is the button, so you can mark without looking"),
    "playback": ("Jump straight to [every mark]", "Playback starts a few seconds early, so you catch the lead-in"),
    "clip": ("Share just [the part that matters]", "A clip around any mark, cut without re-encoding"),
    "search": ("Find any moment [in seconds]", "Search titles, mark names and times"),
    "labels": ("Label marks [as you go]", "Hold Bookmark, slide to Idea, To-do, Quote or Question (Pro)"),
    "private": ("[No account.] No internet.", "Your recordings stay on your phone"),
}
TAGLINE = "Record. Mark the moments. Share the clip."
CHIPS = ["Record", "Mark", "Find", "Clip", "Share"]

ICONS = {  # 24x24 stroke glyphs
    "mark": '<path d="M7 3h10v18l-5-4-5 4z"/>',
    "wave": '<path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 10v4"/>',
    "play": '<path d="M8 5l11 7-11 7z"/>',
    "share": '<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/>'
             '<path d="M8.2 10.8l7.6-3.6M8.2 13.2l7.6 3.6"/>',
    "scissors": '<circle cx="6" cy="7" r="3"/><circle cx="6" cy="17" r="3"/><path d="M8.5 8.5L20 19M8.5 15.5L20 5"/>',
    "search": '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    "tag": '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
    "lock": '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
    "offline": '<path d="M3 3l18 18"/><path d="M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5-2.7M14 10.4A10 10 0 0 1 19 13"/>'
               '<circle cx="12" cy="20" r="1"/>',
}

THEMES = {
    "light": dict(bg="radial-gradient(900px 700px at 100% 0%, #ffe9b8 0%, transparent 70%),"
                     "radial-gradient(800px 800px at 0% 100%, #f6ead2 0%, transparent 70%), #f7f3ea",
                  ink="#14130f", sub="#625b4e", em="background:#ffc23d;color:#14130f;padding:0 .2em;border-radius:.18em",
                  rib="rgba(214,150,20,.08)", line="rgba(190,130,10,.3)", badge="background:#14130f;color:#ffc23d"),
    "night": dict(bg="radial-gradient(1000px 900px at 80% 25%, #3d3115 0%, transparent 65%),"
                     "radial-gradient(800px 700px at 0% 100%, #2a2412 0%, transparent 70%), #14130f",
                  ink="#f3eee2", sub="rgba(243,238,226,.78)", em="color:#ffc23d", rib="rgba(255,194,61,.07)",
                  line="rgba(255,194,61,.32)", badge="background:linear-gradient(145deg,#ffd15a,#f2a81c);color:#14130f"),
    "gold": dict(bg="radial-gradient(900px 900px at 85% 10%, rgba(255,240,190,.55) 0%, transparent 60%),"
                    "linear-gradient(165deg, #ffd15a 0%, #ffc23d 45%, #f2a81c 100%)",
                 ink="#14130f", sub="rgba(20,19,15,.78)", em="color:#ffc23d;background:#14130f;padding:0 .2em;border-radius:.18em",
                 rib="rgba(20,19,15,.06)", line="rgba(20,19,15,.25)", badge="background:#14130f;color:#ffc23d"),
}

CSS = f"@font-face{{font-family:Mona;font-weight:200 900;src:url('{FONT.as_uri()}')}}" + """
*{margin:0;box-sizing:border-box}
html,body{width:1080px;height:1920px;overflow:hidden}
body{font-family:Mona,'Segoe UI',sans-serif;position:relative;-webkit-font-smoothing:antialiased}
.rib{position:absolute;inset:0;width:100%;height:100%}
.cap{position:absolute;top:118px;left:70px;right:70px;text-align:center;z-index:5}
h1{font-weight:780;letter-spacing:-.03em;line-height:1.06;text-wrap:balance}
h1 em{font-style:normal;white-space:nowrap}
.cap p{margin-top:26px;font-size:37px;font-weight:500;line-height:1.3;text-wrap:balance}
.dev{position:absolute;transform-style:preserve-3d}
.dev .edge{position:absolute;inset:0;border-radius:var(--r);background:#0a0a0d;transform:translate(9px,7px)}
.dev .body{position:relative;padding:var(--b);border-radius:var(--r);
  background:linear-gradient(140deg,#4a4a52 0%,#16161b 18%,#0e0e12 60%,#2c2c33 100%);
  box-shadow:0 0 0 1.5px #5a5a63 inset,0 60px 90px -30px rgba(40,25,0,.45),0 30px 50px -25px rgba(0,0,0,.45)}
.dev .scr{position:relative;border-radius:calc(var(--r) - var(--b));overflow:hidden;background:#000}
.dev .scr img{display:block;width:100%}
.dev .cam{position:absolute;top:2.1%;left:50%;width:3.6%;aspect-ratio:1;margin-left:-1.8%;border-radius:50%;
  background:radial-gradient(circle at 35% 35%,#3b3f55 0%,#0b0b10 60%)}
.dev .btn{position:absolute;right:-5px;width:6px;border-radius:3px;background:linear-gradient(90deg,#2a2a30,#55555d)}
.call{position:absolute;border-radius:26px;overflow:hidden;z-index:6;
  box-shadow:0 0 0 5px var(--ring,#fff),0 40px 70px -20px rgba(40,25,0,.45),0 12px 24px -8px rgba(0,0,0,.25)}
.call img{position:absolute;display:block}
.badge{position:absolute;border-radius:50%;display:flex;align-items:center;justify-content:center;z-index:7;
  box-shadow:0 22px 40px -14px rgba(40,25,0,.5),0 4px 10px rgba(0,0,0,.12)}
.badge svg{width:50%;height:50%;fill:none;stroke:currentColor;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}
.blob{position:absolute;border-radius:50%;z-index:0}
"""

# One sound wave crossing every slide, so the set reads as one panorama on the listing.
WAVE_Y = [1480, 1150, 1380, 1720, 1260, 1060, 1460, 1680, 1220, 1420, 1760, 1300, 1100, 1520, 1680]


def wave_path() -> str:
    pts = [(i * 540, y) for i, y in enumerate(WAVE_Y)]
    d = f"M{pts[0][0]} {pts[0][1]}"
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d += f" C{x0 + 220} {y0} {x1 - 220} {y1} {x1} {y1}"
    return d


def ribbon(i: int, t: dict) -> str:
    d = wave_path()
    return (f'<svg class="rib" viewBox="{i * 1080} 0 1080 1920" preserveAspectRatio="none">'
            f'<path d="{d}" fill="none" stroke="{t["rib"]}" stroke-width="170" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{t["line"]}" stroke-width="3" transform="translate(0,-60)"/>'
            f'<path d="{d}" fill="none" stroke="{t["line"]}" stroke-width="1.5" opacity=".6" transform="translate(0,70)"/></svg>')


def clean_screen(raw: Path, out: Path, sb: int, nb: int) -> Path:
    """Replace the system bars (clock, notification icons, navigation) with a neutral status bar and gesture pill."""
    im = Image.open(raw).convert("RGB")
    w, h = im.size
    # Fill each bar with the most common colour of the app row next to it (stretching that row would smear
    # any text it touches into stripes).
    top = max(im.crop((0, sb, w, sb + 1)).getcolors(w), key=lambda c: c[0])[1]
    bot = max(im.crop((0, nb - 1, w, nb)).getcolors(w), key=lambda c: c[0])[1]
    ImageDraw.Draw(im).rectangle((0, 0, w, sb - 1), fill=top)
    ImageDraw.Draw(im).rectangle((0, nb, w, h), fill=bot)
    fg = (30, 28, 24) if sum(top) > 380 else (243, 238, 226)
    d = ImageDraw.Draw(im)
    y = sb // 2 - 56
    font = ImageFont.truetype(str(FONT), 40)
    font.set_variation_by_axes([600, 100]) if hasattr(font, "set_variation_by_axes") else None
    d.text((64, 56 + y), "9:30", font=font, fill=fg, anchor="lm")
    x = w - 64  # battery, wifi, signal (right to left)
    d.rounded_rectangle((x - 52, 40 + y, x - 6, 72 + y), 7, outline=fg, width=3)
    d.rounded_rectangle((x - 47, 45 + y, x - 18, 67 + y), 3, fill=fg)
    d.rectangle((x - 4, 50 + y, x, 62 + y), fill=fg)
    d.pieslice((x - 132, 30 + y, x - 72, 90 + y), 225, 315, fill=fg)
    for k in range(4):
        d.rounded_rectangle((x - 196 + k * 13, 62 - k * 7 + y, x - 187 + k * 13, 72 + y), 2, fill=fg)
    pill = (40, 36, 30) if sum(bot) > 380 else (235, 232, 224)
    d.rounded_rectangle((w // 2 - 150, h - 44, w // 2 + 150, h - 32), 6, fill=pill)
    im.save(out)
    return out


def phone(src: Path, left: int, top: int, width: int, tf: str = "", z: int = 2) -> str:
    b, r = round(width * .022), round(width * .125)
    return (f'<div class="dev" style="left:{left}px;top:{top}px;width:{width}px;--b:{b}px;--r:{r}px;z-index:{z};'
            f'transform:{tf or "none"}"><div class="edge"></div><div class="body"><div class="scr">'
            f'<img src="{src.as_uri()}"><div class="cam"></div></div></div>'
            f'<i class="btn" style="top:{width * .38:.0f}px;height:{width * .2:.0f}px"></i>'
            f'<i class="btn" style="top:{width * .64:.0f}px;height:{width * .12:.0f}px"></i></div>')


def callout(src: Path, box: tuple, left: int, top: int, scale: float, rot: float = 0, ring: str = "#fff") -> str:
    """A real UI region of the capture, enlarged."""
    x0, y0, x1, y1 = box
    return (f'<div class="call" style="--ring:{ring};left:{left}px;top:{top}px;width:{(x1 - x0) * scale:.0f}px;'
            f'height:{(y1 - y0) * scale:.0f}px;transform:rotate({rot}deg)">'
            f'<img src="{src.as_uri()}" style="width:{1080 * scale:.0f}px;left:{-x0 * scale:.0f}px;top:{-y0 * scale:.0f}px"></div>')


def badge(icon: str, left: int, top: int, size: int, t: dict, rot: float = 0) -> str:
    return (f'<div class="badge" style="left:{left}px;top:{top}px;width:{size}px;height:{size}px;{t["badge"]};'
            f'transform:rotate({rot}deg)"><svg viewBox="0 0 24 24">{ICONS[icon]}</svg></div>')


def blob(left: int, top: int, size: int, color: str) -> str:
    return f'<div class="blob" style="left:{left}px;top:{top}px;width:{size}px;height:{size}px;background:{color}"></div>'


# Callout regions in raw 1080x2400 pixels (measured on the captures; re-measure when a capture is retaken).
BOXES = {
    "live.marks": (40, 530, 1040, 840),
    "playback.wave": (30, 440, 1050, 840),
    "clip.range": (30, 1530, 1050, 2010),
    "search.hits": (30, 600, 1050, 1180),
    "private.note": (30, 2030, 1050, 2352),  # from the raw capture: the last line runs under the gesture bar
}

P3 = "perspective(2600px)"
GLOW = "radial-gradient(circle,#ffe1a0 0%,rgba(255,225,160,0) 70%)"
# key: (background, screens needed, body(s, t, b)) — s["light-live"] = clean screen path, b = callout boxes.
SLIDES = {
    "home": ("light", ["dark-live", "light-playback"], lambda s, t, b: (
        blob(-160, 820, 760, GLOW)
        + phone(s["dark-live"], 50, 640, 480, f"{P3} rotateY(22deg) rotateZ(-9deg)", 1)
        + phone(s["light-playback"], 410, 470, 600, f"{P3} rotateY(-10deg) rotateZ(4deg)", 3)
        + badge("mark", 70, 520, 124, t, -8) + badge("wave", 900, 1440, 112, t, 10))),
    "live": ("night", ["dark-live"], lambda s, t, b: (
        phone(s["dark-live"], 330, 540, 610, f"{P3} rotateY(-16deg) rotateZ(3deg)")
        + callout(s["dark-live"], b["live.marks"], 46, 1180, .7, -3, "#2a271f")
        + badge("mark", 110, 960, 120, t, -10))),
    "playback": ("light", ["light-playback"], lambda s, t, b: (
        blob(620, 420, 620, GLOW)
        + phone(s["light-playback"], 205, 560, 670, "rotateZ(-2deg)")
        + callout(s["light-playback"], b["playback.wave"], 120, 1400, .82, 3)
        + badge("play", 70, 760, 124, t, -8))),
    "clip": ("gold", ["light-clip"], lambda s, t, b: (
        phone(s["light-clip"], 50, 560, 590, f"{P3} rotateY(12deg) rotateZ(-3deg)")
        + callout(s["light-clip"], b["clip.range"], 400, 760, .66, -2)
        + badge("scissors", 870, 1240, 112, t, 10))),
    "search": ("light", ["light-search"], lambda s, t, b: (
        blob(-200, 1100, 760, GLOW)
        + phone(s["light-search"], 80, 560, 590, f"{P3} rotateY(14deg) rotateZ(-4deg)")
        + callout(s["light-search"], b["search.hits"], 380, 1270, .66, 3)
        + badge("search", 860, 820, 118, t, 12))),
    "labels": ("night", ["dark-labels"], lambda s, t, b: (
        phone(s["dark-labels"], 235, 540, 610, "rotateZ(2deg)")
        + badge("tag", 110, 900, 124, t, -10))),
    "private": ("gold", ["light-settings"], lambda s, t, b: (
        phone(s["light-settings"], 250, 560, 600, "rotateZ(-2deg)")
        + callout(s["raw:light-settings"], b["private.note"], 60, 1520, .9, -3)
        + badge("lock", 840, 900, 132, t, 8) + badge("offline", 110, 760, 108, t, -10))),
}


def headline(text: str, t: dict) -> str:
    size = 92 if len(text) <= 26 else 84 if len(text) <= 32 else 76
    html = text.replace("[", f'<em style="{t["em"]}">').replace("]", "</em>")
    return f'<h1 style="font-size:{size}px;color:{t["ink"]}">{html}</h1>'


def page(body: str, bg: str, size: tuple) -> str:
    css = CSS.replace("width:1080px;height:1920px", f"width:{size[0]}px;height:{size[1]}px")
    return f'<!doctype html><html lang="en"><meta charset="utf-8"><style>{css}</style><body style="background:{bg}">{body}</body></html>'


def render(html: str, size: tuple, out: Path, src: Path) -> None:
    src.parent.mkdir(parents=True, exist_ok=True)
    src.write_text(html, encoding="utf-8")  # kept as the editable source of the image
    with tempfile.TemporaryDirectory() as tmp:
        shot = Path(tmp) / "shot.png"
        for _ in range(3):  # headless Chrome now and then exits without writing the file
            subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=2",
                            f"--user-data-dir={tmp}/profile", f"--window-size={size[0]},{size[1]}",
                            f"--screenshot={shot}", "--allow-file-access-from-files", src.as_uri()],
                           check=True, capture_output=True, timeout=120)
            if shot.exists():
                break
        im = Image.open(shot).convert("RGB")  # Play wants 24-bit, no alpha
        assert im.size == (size[0] * 2, size[1] * 2), im.size
        out.parent.mkdir(parents=True, exist_ok=True)
        im.resize(size, Image.LANCZOS).save(out, optimize=True)


def slide(n: int, i: int, key: str, screens: dict, out: Path) -> Path:
    theme, _, body = SLIDES[key]
    t = THEMES[theme]
    head, sub = COPY[key]
    cap = f'<div class="cap">{headline(head, t)}<p style="color:{t["sub"]}">{sub}</p></div>'
    body = f'<div style="position:absolute;inset:0;transform:translateY(-40px)">{body(screens, t, BOXES)}</div>'
    dest = out / "screenshots/en" / f"{n:02d}_{key}.png"
    render(page(ribbon(i, t) + cap + body, t["bg"], (1080, 1920)), (1080, 1920), dest, out / "source/en" / f"{n:02d}_{key}.html")
    return dest


def feature(screens: dict, out: Path) -> None:
    t = THEMES["night"]
    chips = "".join(f"<span>{c}</span>" for c in CHIPS)
    css = """<style>
      .fg-logo{position:absolute;left:62px;top:96px;display:flex;align-items:center;gap:22px}
      .fg-logo img{width:118px;height:118px}
      .fg-logo b{font-size:76px;font-weight:800;letter-spacing:-.035em;color:#f3eee2}
      .fg-txt{position:absolute;left:68px;top:258px;width:470px}
      .fg-txt h2{font-size:34px;line-height:1.2;font-weight:700;color:#f3eee2;letter-spacing:-.01em;text-wrap:balance}
      .fg-chips{margin-top:22px;display:flex;flex-wrap:wrap;gap:9px}
      .fg-chips span{font-size:17px;font-weight:650;padding:7px 15px;border-radius:999px;background:#ffc23d;color:#14130f;
        box-shadow:0 6px 14px -6px rgba(0,0,0,.5)}
    </style>"""
    deco = blob(540, -120, 560, "radial-gradient(circle,#ffd15a 0%,#f2a81c 60%,rgba(242,168,28,0) 71%)")
    phones = (phone(screens["light-playback"], 800, 70, 215, f"{P3} rotateY(-12deg) rotateZ(8deg)", 1)
              + phone(screens["dark-live"], 620, 40, 230, f"{P3} rotateY(-8deg) rotateZ(-5deg)", 2))
    body = (css + ribbon(0, t).replace('viewBox="0 0 1080 1920"', 'viewBox="0 900 2160 1000"') + deco + phones
            + f'<div class="fg-logo"><img src="{(BRAND / "logo-mark-1024.png").as_uri()}"><b>Earmark</b></div>'
            + f'<div class="fg-txt"><h2>{TAGLINE}</h2><div class="fg-chips">{chips}</div></div>')
    render(page(body, t["bg"], (1024, 500)), (1024, 500), out / "feature-graphic/feature_graphic_en.png",
           out / "source/en/feature_graphic.html")


def contact_sheet(files: list, out: Path) -> None:
    tw, th, gap = 360, 640, 28
    sheet = Image.new("RGB", (gap + len(files) * (tw + gap), th + 2 * gap), (236, 232, 224))
    for k, f in enumerate(files):
        sheet.paste(Image.open(f).resize((tw, th), Image.LANCZOS), (gap + k * (tw + gap), gap))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, optimize=True)


def main(raw: Path, out: Path) -> None:
    (out / "logo").mkdir(parents=True, exist_ok=True)
    shutil.copy(BRAND / "play-icon-512.png", out / "logo/icon_play_512.png")
    with tempfile.TemporaryDirectory() as tmp:
        screens = {p.stem: clean_screen(p, Path(tmp) / p.name, *BARS) for p in raw.glob("*.png")}
        screens |= {f"raw:{p.stem}": p for p in raw.glob("*.png")}  # uncleaned, for callouts near the bars
        keys = [k for k in SLIDES if all(x in screens for x in SLIDES[k][1])]
        made = [slide(n, list(SLIDES).index(k), k, screens, out) for n, k in enumerate(keys, 1)]
        if made:
            contact_sheet(made, out / "previews/contact_sheet_en.png")
        feature(screens, out)
        print(len(made), "screenshots + feature graphic; missing:", [k for k in SLIDES if k not in keys])


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
