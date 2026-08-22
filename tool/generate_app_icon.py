#!/usr/bin/env python3
"""Janus WebRTC Client 앱 아이콘 생성기.

1024x1024 마스터를 코드로 그린 뒤 iOS/Android 런처 리소스를 한 번에 뽑는다.
색/형태를 바꾸려면 아래 상수만 고치고 `python3 tool/generate_app_icon.py` 를 다시 돌리면 된다.

  모티브: 주고받는 말풍선(통화) + 좌우로 퍼지는 시그널 아크(WebRTC).
  가운데 글리프는 `assets/icon/glyph_source.png` 를 그대로 얹는다.

같은 좌표계를 Flutter 쪽 JanusMark 위젯이 그대로 쓰므로, 글리프를 고치면
`assets/icon/call_glyph.png` 가 다시 생성되어 앱 화면에도 함께 반영된다.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
U = 1024.0  # 도형 좌표계 기준 크기

# ── 배경 팔레트 ───────────────────────────────────────────────────────────────
BG_STOPS = [(0.00, (139, 92, 246)), (0.45, (79, 70, 229)), (1.00, (12, 18, 43))]
GLOW_CYAN = ((0.84, 0.16), 0.58, (34, 211, 238), 0.50)   # (중심), 반경, 색, 세기
GLOW_PINK = ((0.14, 0.88), 0.55, (244, 114, 182), 0.45)

# ── 가운데 글리프 ─────────────────────────────────────────────────────────────
# 직접 그리지 않고 준비된 그림을 그대로 얹는다. 바꾸려면 이 파일만 교체하면 된다.
GLYPH_SOURCE = ROOT / "assets/icon/glyph_source.png"
GLYPH_CENTER = (512, 496)
GLYPH_SIZE = 450          # 긴 변 기준, 1024 좌표계. 아크와 붙지 않을 만큼
GLYPH_GLOW = (56, 189, 248)
MONO_CUT = 212            # 이보다 밝은 픽셀은 테마 아이콘에서 파낸다

# ── 시그널 아크 ───────────────────────────────────────────────────────────────
ARC_RIGHT = (103, 232, 249)
ARC_LEFT = (249, 168, 212)
ARC_CENTER = (512, 500)
ARC_SPAN = 50                 # 중심선 기준 ±각도
ARCS = [(330, 26, 1.00), (400, 20, 0.62)]  # 반경, 두께, 알파

# 마크가 차지하는 영역. Flutter 의 JanusMark 도 같은 값을 쓴다.
CONTENT = (100, 176, 924, 824)


def draw_glyph(size: int = 2560, mono: bool = False) -> Image.Image:
    """가운데 글리프만 담은 레이어(아크 없음). Flutter 위젯도 이 그림을 쓴다."""
    if not GLYPH_SOURCE.exists():
        raise FileNotFoundError(f"글리프 원본이 없습니다: {GLYPH_SOURCE}")
    src = Image.open(GLYPH_SOURCE).convert("RGBA")
    src = src.crop(src.getbbox())  # 원본 여백은 버리고 우리 여백을 쓴다

    scale = size / U
    target = GLYPH_SIZE * scale
    ratio = target / max(src.size)
    art = src.resize((max(int(src.size[0] * ratio), 1),
                      max(int(src.size[1] * ratio), 1)), Image.LANCZOS)

    if mono:
        # 테마 아이콘은 한 색뿐이라 실루엣만 남는다. 그대로 두면 덩어리로 뭉치므로
        # 원본에서 밝은 부분(말풍선 안 글줄)을 파내 형태를 살린다.
        rgb = np.asarray(art.convert("RGB"), dtype=np.float32)
        luma = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        keep = np.array(art.split()[3], dtype=np.float32)
        keep *= np.clip((MONO_CUT - luma) / 24.0, 0.0, 1.0)  # 경계는 부드럽게
        white = Image.new("RGBA", art.size, (255, 255, 255, 255))
        white.putalpha(Image.fromarray(keep.astype(np.uint8)))
        art = white

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.paste(art, (int(GLYPH_CENTER[0] * scale - art.size[0] / 2),
                      int(GLYPH_CENTER[1] * scale - art.size[1] / 2)), art)
    return layer


def draw_arcs(size: int, mono: bool) -> Image.Image:
    scale = size / U
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = ARC_CENTER[0] * scale, ARC_CENTER[1] * scale
    for radius, width, alpha in ARCS:
        r = radius * scale
        box = (cx - r, cy - r, cx + r, cy + r)
        a = int(255 * alpha)
        right = (255, 255, 255, a) if mono else ARC_RIGHT + (a,)
        left = (255, 255, 255, a) if mono else ARC_LEFT + (a,)
        d.arc(box, -ARC_SPAN, ARC_SPAN, fill=right, width=int(width * scale))
        d.arc(box, 180 - ARC_SPAN, 180 + ARC_SPAN, fill=left, width=int(width * scale))
    return layer


def draw_mark(size: int = 2560, mono: bool = False) -> Image.Image:
    layer = draw_arcs(size, mono)
    glyph = draw_glyph(size, mono)
    if not mono:  # 수화기 뒤 은은한 광원
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        glow.paste(GLYPH_GLOW + (190,), (0, 0), glyph.split()[3])
        layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(size * 0.022)))
    layer.alpha_composite(glyph)
    return layer


def make_background(size: int) -> Image.Image:
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / max(size - 1, 1)
    t = np.clip((xx * 0.45 + yy * 0.85) / 1.30, 0.0, 1.0)
    rgb = np.zeros((size, size, 3), dtype=np.float32)
    for (t0, c0), (t1, c1) in zip(BG_STOPS, BG_STOPS[1:]):
        m = (t >= t0) & (t <= t1)
        k = ((t - t0) / (t1 - t0))[..., None]
        rgb[m] = (np.array(c0, np.float32)
                  + (np.array(c1, np.float32) - np.array(c0, np.float32)) * k)[m]

    for (cx, cy), radius, color, strength in (GLOW_CYAN, GLOW_PINK):
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / radius
        falloff = (np.exp(-(d**2) * 1.6) * strength)[..., None]
        rgb = rgb + (np.array(color, np.float32) - rgb) * falloff

    vignette = (1.0 - 0.30 * np.clip(
        np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2) / 0.72, 0, 1) ** 2.2)[..., None]
    return Image.fromarray(np.clip(rgb * vignette, 0, 255).astype(np.uint8))


_MARK_CACHE: dict[bool, Image.Image] = {}


def mark(mono: bool = False) -> Image.Image:
    if mono not in _MARK_CACHE:
        img = draw_mark(mono=mono)
        scale = img.size[0] / U
        box = tuple(int(round(v * scale)) for v in CONTENT)
        _MARK_CACHE[mono] = img.crop(box)
    return _MARK_CACHE[mono]


def place_mark(canvas: Image.Image, frac: float, mono: bool = False,
               shadow: bool = True) -> Image.Image:
    """마크를 캔버스 정중앙에 frac 비율로 배치한다."""
    size = canvas.size[0]
    src = mark(mono)
    target = max(int(size * frac), 1)
    ratio = target / max(src.size)
    scaled = src.resize((max(int(src.size[0] * ratio), 1),
                         max(int(src.size[1] * ratio), 1)), Image.LANCZOS)
    ox = (size - scaled.size[0]) // 2
    oy = (size - scaled.size[1]) // 2

    out = canvas.convert("RGBA")
    if shadow and not mono:
        shade = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        shade.paste((10, 8, 40, 150), (ox, oy + int(size * 0.018)), scaled.split()[3])
        out.alpha_composite(shade.filter(ImageFilter.GaussianBlur(size * 0.022)))

    top = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    top.paste(scaled, (ox, oy), scaled)
    out.alpha_composite(top)
    return out


def rounded_mask(size: int, radius_frac: float) -> Image.Image:
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1),
        radius=int(size * ss * radius_frac), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def circle_mask(size: int) -> Image.Image:
    ss = 4
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size * ss - 1, size * ss - 1), fill=255)
    return m.resize((size, size), Image.LANCZOS)


MASTER = 1536  # 각 산출물은 마스터에서 축소해 계단현상을 줄인다


def master_full() -> Image.Image:
    return place_mark(make_background(MASTER), 0.76).convert("RGB")


def save(img: Image.Image, rel: str, size: int, mode: str = "RGB") -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS).convert(mode)
    out.save(path)
    print(f"  {rel} ({size}x{size})")


def main() -> None:
    full = master_full()
    fg = place_mark(Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0)), 0.60)
    fg_mono = place_mark(Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0)), 0.60,
                         mono=True)
    bg_only = make_background(MASTER).convert("RGB")

    rounded = full.convert("RGBA")
    rounded.putalpha(rounded_mask(MASTER, 0.225))
    circled = full.convert("RGBA")
    circled.putalpha(circle_mask(MASTER))

    print("소스 마스터")
    save(full, "assets/icon/app_icon.png", 1024)
    save(fg, "assets/icon/app_icon_foreground.png", 1024, "RGBA")
    save(bg_only, "assets/icon/app_icon_background.png", 1024)
    # Flutter JanusMark 위젯이 쓰는 수화기 레이어(1024 좌표계 그대로).
    save(draw_glyph(), "assets/icon/call_glyph.png", 1024, "RGBA")

    print("iOS AppIcon.appiconset")
    contents = json.loads(
        (ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text())
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    seen = set()
    for entry in contents["images"]:
        name = entry["filename"]
        if name in seen:
            continue
        seen.add(name)
        base = float(entry["size"].split("x")[0])
        px = int(round(base * float(entry["scale"].rstrip("x"))))
        save(full, f"{ios_dir}/{name}", px)  # iOS 아이콘은 알파 금지 → RGB

    print("Android 런처")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dpi, px in legacy.items():
        save(rounded, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher.png", px, "RGBA")
        save(circled, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher_round.png", px, "RGBA")
    for dpi, px in adaptive.items():
        save(fg, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher_foreground.png", px, "RGBA")
        save(bg_only, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher_background.png", px)
        save(fg_mono, f"android/app/src/main/res/mipmap-{dpi}/ic_launcher_monochrome.png", px, "RGBA")

    print("완료")


if __name__ == "__main__":
    main()
