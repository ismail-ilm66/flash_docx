"""Dumps the owner's reference pipeline outputs for the Dart parity tests.

For each photo in test/fixtures/edges/*.jpg:
  * <name>.json            detected corners (normalised TL,TR,BR,BL), score, map
  * reference/<name>_warp.png        reference warp (lossless), the shared input
  * reference/<name>_auto.png        filter_auto_color(warp)
  * reference/<name>_id.png          filter_id_color(warp)
  * reference/<name>_bw.png          filter_bw_print(warp)
  * reference/<name>_ocr.png         ocr_image(warp)
  * reference/<name>_dnprev.png      denoise_preview(warp) (round 6)
  * reference/<name>_blur.json       blurry_regions(warp) cells, and of a
                                     copy with its right third blurred
  * reference/<name>_noisy*.png      warp + seeded noise (σ 6), its Auto and
                                     ID colour: exercises the NLM denoise
  * reference/<name>_overlay.jpg     photo with the detected quad, for review
  * reference/<name>_small.png       the downscaled photo detection works on
  * reference/<name>_map_<map>.png   each candidate map on it (round 5, P0-4)
  * reference/<name>_boost/_gray.png   Colour boost / Grayscale (round 11)
  * reference/<name>_border.png       clean_page_border(Auto)
  * reference/<name>_curved.png       warp_curved (Document photos)
  * reference/<name>_r11.json         find_fingers / page_fills_frame results
  * reference/synthetic_*             a bent page and a thumb (no private photos)
Run: python3 tool/reference/dump_reference.py
"""
import glob, json, os, sys
import cv2 as cv
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import flashdox_reference as ref  # noqa: E402

root = os.path.join(os.path.dirname(__file__), '..', '..', 'test', 'fixtures')
edges = os.path.join(root, 'edges')
out = os.path.join(root, 'reference')
os.makedirs(out, exist_ok=True)
for p in sorted(glob.glob(os.path.join(edges, '*.jpg'))):
    name = os.path.splitext(os.path.basename(p))[0]
    mode = 'id' if name.startswith('id_') else 'document'
    img = cv.imread(p)
    h, w = img.shape[:2]
    q, score, src = ref.detect_document(img, mode)
    if q is None:
        print(f'{name}: NOT FOUND'); continue
    q = ref._order_corners(q)
    meta = {k: [round(float(x) / w, 5), round(float(y) / h, 5)] for k, (x, y) in zip(['tl', 'tr', 'br', 'bl'], q)}
    meta.update({'source': 'reference detect_document (owner photo)', 'map': src, 'score': round(score, 4)})
    if mode == 'id':
        meta['aspect'] = ref.ID_ASPECT
    side = os.path.join(edges, name + '.json')
    if os.path.exists(side):
        # Never overwrite hand-marked corners: only refresh what the
        # reference found, which the parity test compares against.
        old = json.load(open(side))
        old['reference_found'] = {k: meta[k] for k in ['tl', 'tr', 'br', 'bl']}
        old['map'], old['score'] = meta['map'], meta['score']
        meta = old
    json.dump(meta, open(side, 'w'), indent=1)
    warped = ref.warp(img, q, mode)
    cv.imwrite(os.path.join(out, f'{name}_warp.png'), warped)
    cv.imwrite(os.path.join(out, f'{name}_auto.png'), ref.filter_auto_color(warped))
    cv.imwrite(os.path.join(out, f'{name}_id.png'), ref.filter_id_color(warped))
    cv.imwrite(os.path.join(out, f'{name}_bw.png'), ref.filter_bw_print(warped))
    cv.imwrite(os.path.join(out, f'{name}_ocr.png'), ref.ocr_image(warped))
    cv.imwrite(os.path.join(out, f'{name}_dnprev.png'), ref.denoise_preview(warped))
    # Round 11: the filters built on flatten_page, the page border clean-up,
    # the bent-page warp and the finger check.
    cv.imwrite(os.path.join(out, f'{name}_boost.png'), ref.filter_color_boost(warped))
    cv.imwrite(os.path.join(out, f'{name}_gray.png'), ref.filter_grayscale(warped))
    cv.imwrite(os.path.join(out, f'{name}_border.png'), ref.clean_page_border(ref.filter_auto_color(warped)))
    if mode == 'document':
        cv.imwrite(os.path.join(out, f'{name}_curved.png'), ref.warp_curved(img, q, mode))
    json.dump({'fingers': ref.find_fingers(warped) is not None,
               'fills_imported': bool(ref.page_fills_frame(warped, True)),
               'fills_photo': bool(ref.page_fills_frame(img, False))},
              open(os.path.join(out, f'{name}_r11.json'), 'w'))
    # Camera shake on one side (round 6, P1-1): the right third blurred.
    shaken = warped.copy()
    x0 = shaken.shape[1] * 2 // 3
    shaken[:, x0:] = cv.GaussianBlur(shaken[:, x0:], (0, 0), 3.0)
    cv.imwrite(os.path.join(out, f'{name}_shaken.png'), shaken)
    # Dim-light sensor noise, so the fast denoise's NLM path is compared too.
    noise = np.random.default_rng(6).normal(0, 6, warped.shape)
    noisy = np.clip(warped.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    cv.imwrite(os.path.join(out, f'{name}_noisy.png'), noisy)
    cv.imwrite(os.path.join(out, f'{name}_noisy_auto.png'), ref.filter_auto_color(noisy))
    cv.imwrite(os.path.join(out, f'{name}_noisy_id.png'), ref.filter_id_color(noisy))
    json.dump({'warp': [list(c) for c in ref.blurry_regions(warped)],
               'shaken': [list(c) for c in ref.blurry_regions(shaken)]},
              open(os.path.join(out, f'{name}_blur.json'), 'w'))
    s = ref.DETECT_LONG_EDGE / max(h, w)
    small = cv.resize(img, (int(w * s), int(h * s)), interpolation=cv.INTER_AREA) if s < 1 else img.copy()
    cv.imwrite(os.path.join(out, f'{name}_small.png'), small)
    for mname, bmap in ref._candidate_maps(small):
        cv.imwrite(os.path.join(out, f'{name}_map_{mname.replace("+", "_")}.png'), bmap)
    vis = img.copy()
    cv.polylines(vis, [q.astype(np.int32)], True, (0, 220, 0), 4)
    cv.imwrite(os.path.join(out, f'{name}_overlay.jpg'), vis)
    print(f'{name}: {w}x{h} found via {src} score={score:.3f} sharpness={ref.sharpness(img):.0f} corners={meta["tl"]},{meta["tr"]},{meta["br"]},{meta["bl"]}')


# Round 11 synthetic cases (no private photos in the repository).
def bent_photo():
    """A page whose top and bottom edges bow outwards, on a dark table."""
    H, W = 900, 1200
    img = np.full((H, W, 3), (90, 70, 50), np.uint8)  # blue-grey: brown passes the skin rule
    xs = np.arange(250, 951)
    t = (xs - 250) / 700.0
    top = 120 - 25 * np.sin(np.pi * t)
    bot = 780 + 30 * np.sin(np.pi * t)
    poly = np.concatenate([np.stack([xs, top], 1), np.stack([xs[::-1], bot[::-1]], 1)]).astype(np.int32)
    cv.fillPoly(img, [poly], (235, 238, 240))
    for k in range(12):
        f = (k + 1) / 13
        ys = top + (bot - top) * f
        cv.polylines(img, [np.stack([xs[40:-40], ys[40:-40]], 1).astype(np.int32)], False, (40, 40, 40), 3)
    noise = np.random.default_rng(11).normal(0, 2, img.shape)
    return np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)


bent = bent_photo()
cv.imwrite(os.path.join(out, 'synthetic_bent_photo.png'), bent)
q, score, src = ref.detect_document(bent, 'document')
q = ref._order_corners(q)
bh, bw = bent.shape[:2]
json.dump({'quad': [[float(x) / bw, float(y) / bh] for x, y in q], 'source': src},
          open(os.path.join(out, 'synthetic_bent.json'), 'w'), indent=1)
cv.imwrite(os.path.join(out, 'synthetic_bent_curved.png'), ref.warp_curved(bent, q, 'document'))
cv.imwrite(os.path.join(out, 'synthetic_bent_fixed.png'), ref.warp_curved(bent, q, 'document', corners_fixed=True))
print(f'synthetic bent page: {src}, curved {ref.warp_curved(bent, q).shape}, plain {ref.warp(bent, q).shape}')


def thumb_page():
    """The letter page with a thumb coming in from the bottom edge."""
    page = cv.imread(os.path.join(out, 'letter_page_warp.png'))
    H, W = page.shape[:2]
    cv.ellipse(page, (int(W * 0.6), H), (int(W * 0.06), int(H * 0.12)), 0, 0, 360, (120, 150, 210), -1)
    cv.ellipse(page, (int(W * 0.6), int(H * 0.93)), (int(W * 0.03), int(H * 0.025)), 0, 0, 360, (150, 170, 225), -1)
    return cv.GaussianBlur(page, (0, 0), 1.0)


thumb = thumb_page()
cv.imwrite(os.path.join(out, 'synthetic_thumb.png'), thumb)
mask = ref.find_fingers(thumb)
assert mask is not None, 'reference finds no finger on the synthetic thumb'
cv.imwrite(os.path.join(out, 'synthetic_thumb_mask.png'), mask)
cv.imwrite(os.path.join(out, 'synthetic_thumb_removed.png'), ref.remove_fingers(ref.filter_auto_color(thumb), mask))
print(f'synthetic thumb: mask {cv.countNonZero(mask) / mask.size:.2%} of the page')
