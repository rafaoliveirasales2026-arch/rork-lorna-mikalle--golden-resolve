"""Cleans Lorna's generated base-colour texture without changing her design.

The model's UV layout is untouched: this only repaints the 1024 px atlas from
lorna_mikalle.usdz into a 2048 px atlas that the game applies at runtime to the
base model and every animation clip (the clips ship a blurrier 512 px copy).

Steps: Lanczos upscale -> median filter (removes smudges, speckles and streaks
while keeping edges) -> soft snap of every pixel toward the nearest of the
atlas's own dominant colours (k-means), which evens out irregular patches into
clean anime-style colour regions -> light unsharp mask for crisp transitions.

Usage: python3 tools/clean_lorna_texture.py <extracted_image_0.jpg> <out.jpg>
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

SRC, DST = sys.argv[1], sys.argv[2]
K = 26          # dominant colours kept (jacket, shadows, scarf stripes, jeans, fur, hair, skin, eyes...)
SNAP = 0.72     # how strongly each pixel moves to its colour region (1 = flat cel colour)

img = Image.open(SRC).convert("RGB")
img = img.filter(ImageFilter.MedianFilter(3))
big = img.resize((2048, 2048), Image.LANCZOS)
big = big.filter(ImageFilter.MedianFilter(5)).filter(ImageFilter.MedianFilter(3))

px = np.asarray(big, dtype=np.float32) / 255.0
flat = px.reshape(-1, 3)

# Fit k-means on a sample (deterministic), in a lightly perceptual space.
rng = np.random.default_rng(16)
sample = flat[rng.choice(len(flat), 120_000, replace=False)]
weights = np.array([1.0, 1.2, 0.9], dtype=np.float32)
# Reference colours pinned so cleanup can never drift them (cool grey-white fur, jacket, scarf, black).
PINNED = np.array([
    [0.93, 0.94, 0.96], [0.78, 0.80, 0.85],                 # fur shoulders, light + shade
    [0xF2 / 255, 0xC2 / 255, 0x4B / 255],                   # mustard jacket
    [0x2E / 255, 0x9A / 255, 0xD0 / 255],                   # scarf blue
    [0.08, 0.06, 0.07],                                     # shoes / outlines
], dtype=np.float32)
NP = len(PINNED)
centers = np.concatenate([PINNED, sample[rng.choice(len(sample), K, replace=False)]]).astype(np.float32)
for _ in range(25):
    d = (((sample[:, None, :] - centers[None]) * weights) ** 2).sum(-1)
    label = d.argmin(1)
    for k in range(NP, len(centers)):
        members = sample[label == k]
        if len(members):
            centers[k] = members.mean(0)

labels = np.empty(len(flat), dtype=np.int32)
second = np.empty(len(flat), dtype=np.float32)
for start in range(0, len(flat), 262_144):
    chunk = flat[start:start + 262_144]
    d = (((chunk[:, None, :] - centers[None]) * weights) ** 2).sum(-1)
    order = np.argsort(d, axis=1)
    labels[start:start + len(chunk)] = order[:, 0]
    # Pixels that sit between two colours (true edges, eye highlights) are snapped less.
    d0 = np.take_along_axis(d, order[:, :1], 1)[:, 0]
    d1 = np.take_along_axis(d, order[:, 1:2], 1)[:, 0]
    second[start:start + len(chunk)] = np.clip((d1 - d0) / (d1 + 1e-6), 0, 1)

snap = (SNAP * (0.35 + 0.65 * second))[:, None]
cleaned = flat * (1 - snap) + centers[labels] * snap
out = Image.fromarray((cleaned.reshape(px.shape) * 255).clip(0, 255).astype(np.uint8))
out = out.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
out.save(DST, quality=92, subsampling=0, optimize=True)
print("saved", DST, out.size)
