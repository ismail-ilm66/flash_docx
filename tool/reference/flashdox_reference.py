"""
Flash Dox — reference pipeline for edge detection and enhancement.

Written in Python + OpenCV so it can be run and verified on real photos.
Every call used here exists in opencv_dart with the same name
(cv.cvtColor, cv.GaussianBlur, cv.Canny, cv.findContours, cv.approxPolyDP,
cv.convexHull, cv.minAreaRect, cv.getPerspectiveTransform, cv.warpPerspective,
cv.createCLAHE, cv.bilateralFilter, cv.adaptiveThreshold, cv.medianBlur ...),
so the Dart port is a line-by-line translation.

Usage:
    python3 flashdox_reference.py <input_dir> <output_dir> [--mode document|id|passport]
"""
from __future__ import annotations

import sys
import os
import glob
import numpy as np
import cv2 as cv

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DETECT_LONG_EDGE = 800          # detection runs on a small copy -> fast on low-end phones
MIN_AREA_FRAC = 0.05            # ignore shapes smaller than 5% of the photo
ID_ASPECT = 85.6 / 54.0         # ID-1 card (CNIC, driving licence)
PASSPORT_ASPECT = 125.0 / 88.0  # ID-3 passport data page


# ---------------------------------------------------------------------------
# 1. Edge detection
# ---------------------------------------------------------------------------
def _order_corners(pts: np.ndarray) -> np.ndarray:
    """Return corners as TL, TR, BR, BL."""
    pts = pts.reshape(4, 2).astype(np.float32)
    s = pts.sum(axis=1)
    d = np.diff(pts, axis=1).ravel()           # y - x
    return np.array([pts[np.argmin(s)], pts[np.argmin(d)],
                     pts[np.argmax(s)], pts[np.argmax(d)]], dtype=np.float32)


def _corner_angles_score(q: np.ndarray) -> float:
    """1.0 = perfect rectangle, lower = more skewed."""
    errs = []
    for i in range(4):
        a, b, c = q[i - 1], q[i], q[(i + 1) % 4]
        v1, v2 = a - b, c - b
        cosang = abs(np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-6))
        errs.append(cosang)                    # 0 at 90 degrees
    return float(max(0.0, 1.0 - 2.0 * np.mean(errs)))


def _aspect(q: np.ndarray) -> float:
    w = (np.linalg.norm(q[1] - q[0]) + np.linalg.norm(q[2] - q[3])) / 2
    h = (np.linalg.norm(q[3] - q[0]) + np.linalg.norm(q[2] - q[1])) / 2
    return max(w, h) / max(1e-6, min(w, h))


def _quad_from_contour(c: np.ndarray) -> np.ndarray | None:
    hull = cv.convexHull(c)
    peri = cv.arcLength(hull, True)
    for eps in (0.02, 0.03, 0.04, 0.06, 0.08):
        approx = cv.approxPolyDP(hull, eps * peri, True)
        if len(approx) == 4:
            return approx.reshape(4, 2).astype(np.float32)
    # Rounded corners (ID cards) or a slightly bent page: use the min-area rectangle
    # when the shape fills it well.
    rect = cv.minAreaRect(hull)
    box = cv.boxPoints(rect)
    if cv.contourArea(hull) / max(1.0, cv.contourArea(box)) > 0.90:
        return box.astype(np.float32)
    return None


def _candidate_maps(small: np.ndarray) -> list[tuple[str, np.ndarray]]:
    """Several binary maps; each one finds documents in different conditions."""
    gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY)
    lab = cv.cvtColor(small, cv.COLOR_BGR2LAB)
    hsv = cv.cvtColor(small, cv.COLOR_BGR2HSV)
    maps = []

    # A) Edges, thresholds from the median brightness (works on most photos)
    blur = cv.GaussianBlur(gray, (5, 5), 0)
    m = float(np.median(blur))
    lo, hi = int(max(10, 0.66 * m)), int(min(255, max(40, 1.33 * m)))
    edges = cv.Canny(blur, lo, hi)
    k = cv.getStructuringElement(cv.MORPH_RECT, (5, 5))
    edges = cv.morphologyEx(edges, cv.MORPH_CLOSE, k, iterations=2)
    edges = cv.dilate(edges, k, iterations=1)
    # Close shapes that run off the photo (page partly outside the frame):
    cv.rectangle(edges, (0, 0), (edges.shape[1] - 1, edges.shape[0] - 1), 255, 2)
    maps.append(("edges", edges))

    # B) Brightness regions: pale paper/card on a darker surface (Otsu on L)
    L = cv.GaussianBlur(lab[:, :, 0], (7, 7), 0)
    _, th = cv.threshold(L, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU)
    k2 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9))
    th = cv.morphologyEx(th, cv.MORPH_OPEN, k2)
    th = cv.morphologyEx(th, cv.MORPH_CLOSE, k2, iterations=2)
    maps.append(("bright", th))

    # C) Low saturation regions: white/grey paper on a colourful surface
    S = cv.GaussianBlur(hsv[:, :, 1], (7, 7), 0)
    _, ts = cv.threshold(S, 0, 255, cv.THRESH_BINARY_INV + cv.THRESH_OTSU)
    ts = cv.morphologyEx(ts, cv.MORPH_OPEN, k2)
    ts = cv.morphologyEx(ts, cv.MORPH_CLOSE, k2, iterations=2)
    maps.append(("lowsat", ts))
    return maps


def detect_document(bgr: np.ndarray, mode: str = "document"):
    """
    Returns (corners TL,TR,BR,BL in full-resolution pixel coords, score, source)
    or (None, 0, None) when nothing convincing is found.
    """
    H, W = bgr.shape[:2]
    scale = DETECT_LONG_EDGE / max(H, W)
    small = cv.resize(bgr, (int(W * scale), int(H * scale)), interpolation=cv.INTER_AREA) if scale < 1 else bgr.copy()
    if scale >= 1:
        scale = 1.0
    h, w = small.shape[:2]
    img_area = float(h * w)

    target = {"id": ID_ASPECT, "passport": PASSPORT_ASPECT}.get(mode)
    best, best_score, best_src = None, 0.0, None

    for name, bmap in _candidate_maps(small):
        retr = cv.RETR_LIST if name == "edges" else cv.RETR_EXTERNAL
        contours, _ = cv.findContours(bmap, retr, cv.CHAIN_APPROX_SIMPLE)
        for c in contours:
            area = cv.contourArea(c)
            if area < MIN_AREA_FRAC * img_area:
                continue
            q = _quad_from_contour(c)
            if q is None:
                continue
            q = _order_corners(q)
            if name != "edges":
                # Region maps sit slightly inside the real edge (dark rim, rounded
                # corners) -> push corners 2% outward from the centre.
                cxy = q.mean(axis=0)
                q = cxy + (q - cxy) * 1.02
                q[:, 0] = np.clip(q[:, 0], 0, w - 1)
                q[:, 1] = np.clip(q[:, 1], 0, h - 1)
            qa = cv.contourArea(q)
            frac = qa / img_area
            if frac > 0.98:                    # that's just the photo border
                continue
            # Reject the photo frame itself: 3+ corners hugging the border.
            m = 0.02 * max(w, h)
            on_border = sum(1 for x, y in q if x < m or y < m or x > w - 1 - m or y > h - 1 - m)
            if on_border >= 3:
                continue
            rect = _corner_angles_score(q)
            if rect < 0.55:
                continue
            solidity = min(1.0, area / max(1.0, qa))
            score = frac ** 0.5 * rect * (0.5 + 0.5 * solidity)
            if target:
                a = _aspect(q)
                score *= max(0.05, 1.0 - abs(a - target) / target * 2.5)
            if score > best_score:
                best, best_score, best_src = q, score, name

    if best is None:
        return None, 0.0, None
    return best / scale, best_score, best_src


def fallback_quad(W: int, H: int, guide: tuple | None = None) -> np.ndarray:
    """Never the exact full frame. ID/Passport: the on-screen guide frame mapped to the photo."""
    if guide is not None:
        x0, y0, x1, y1 = guide
        return np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]], dtype=np.float32)
    i = 0.05
    return np.array([[W * i, H * i], [W * (1 - i), H * i],
                     [W * (1 - i), H * (1 - i)], [W * i, H * (1 - i)]], dtype=np.float32)


# ---------------------------------------------------------------------------
# 2. Perspective warp
# ---------------------------------------------------------------------------
def warp(bgr: np.ndarray, q: np.ndarray, mode: str = "document") -> np.ndarray:
    q = _order_corners(q)
    wA = np.linalg.norm(q[2] - q[3]); wB = np.linalg.norm(q[1] - q[0])
    hA = np.linalg.norm(q[1] - q[2]); hB = np.linalg.norm(q[0] - q[3])
    Wt, Ht = int(max(wA, wB)), int(max(hA, hB))
    target = {"id": ID_ASPECT, "passport": PASSPORT_ASPECT}.get(mode)
    if target:                                 # force the real card shape
        if Wt >= Ht:
            Ht = int(round(Wt / target))
        else:
            Wt = int(round(Ht / target))
    dst = np.array([[0, 0], [Wt - 1, 0], [Wt - 1, Ht - 1], [0, Ht - 1]], dtype=np.float32)
    M = cv.getPerspectiveTransform(q, dst)
    return cv.warpPerspective(bgr, M, (Wt, Ht), flags=cv.INTER_CUBIC, borderMode=cv.BORDER_REPLICATE)


# ---------------------------------------------------------------------------
# 3. Filters (always applied AFTER the warp)
# ---------------------------------------------------------------------------
def _gray_world_wb(bgr: np.ndarray, strength: float = 0.7) -> np.ndarray:
    f = bgr.astype(np.float32)
    means = f.reshape(-1, 3).mean(axis=0)
    gain = means.mean() / np.maximum(means, 1.0)
    gain = 1.0 + (gain - 1.0) * strength
    return np.clip(f * gain, 0, 255).astype(np.uint8)


def _clahe_L(bgr: np.ndarray, clip: float) -> np.ndarray:
    lab = cv.cvtColor(bgr, cv.COLOR_BGR2LAB)
    clahe = cv.createCLAHE(clipLimit=clip, tileGridSize=(8, 8))
    lab[:, :, 0] = clahe.apply(lab[:, :, 0])
    return cv.cvtColor(lab, cv.COLOR_LAB2BGR)


def _saturate(bgr: np.ndarray, factor: float) -> np.ndarray:
    hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV).astype(np.float32)
    hsv[:, :, 1] = np.clip(hsv[:, :, 1] * factor, 0, 255)
    return cv.cvtColor(hsv.astype(np.uint8), cv.COLOR_HSV2BGR)


def _unsharp(bgr: np.ndarray, amount: float, sigma: float) -> np.ndarray:
    blur = cv.GaussianBlur(bgr, (0, 0), sigma)
    return cv.addWeighted(bgr, 1 + amount, blur, -amount, 0)


def _denoise(bgr: np.ndarray) -> np.ndarray:
    """Remove sensor noise BEFORE any contrast step (otherwise it gets amplified).
    Non-local means is the strongest; it runs on a <= 2000 px copy for speed and the
    clean result is upscaled only if the input was larger. Fallback: bilateral."""
    h, w = bgr.shape[:2]
    s = min(1.0, 2000.0 / max(h, w))
    small = cv.resize(bgr, (int(w * s), int(h * s)), interpolation=cv.INTER_AREA) if s < 1 else bgr
    try:
        clean = cv.fastNlMeansDenoisingColored(small, None, 5, 5, 7, 21)
    except Exception:
        clean = cv.bilateralFilter(small, 7, 40, 40)
    if s < 1:
        # keep full-res detail: add back the fine detail of the original minus its noise-scale blur
        up = cv.resize(clean, (w, h), interpolation=cv.INTER_CUBIC)
        detail = cv.subtract(bgr, cv.GaussianBlur(bgr, (0, 0), 1.5), dtype=cv.CV_16S)
        return np.clip(up.astype(np.int16) + (detail * 0.5).astype(np.int16), 0, 255).astype(np.uint8)
    return clean


def _background(gray_or_ch: np.ndarray) -> np.ndarray:
    """Estimate paper brightness (illumination) without the text."""
    h, w = gray_or_ch.shape[:2]
    s = 400.0 / max(h, w)
    small = cv.resize(gray_or_ch, (max(1, int(w * s)), max(1, int(h * s))), interpolation=cv.INTER_AREA)
    k = cv.getStructuringElement(cv.MORPH_RECT, (9, 9))
    small = cv.dilate(small, k)                # remove dark text strokes
    small = cv.medianBlur(small, 21).astype(np.float32)
    small = cv.GaussianBlur(small, (0, 0), 6)  # float + blur -> no banding steps
    return cv.resize(small, (w, h), interpolation=cv.INTER_CUBIC)


def filter_auto_color(bgr: np.ndarray) -> np.ndarray:
    """Default 'Auto': clean, bright page, colours kept. For paper documents."""
    img = _denoise(bgr)
    img = _gray_world_wb(img, 0.6)
    f = img.astype(np.float32)
    out = np.empty_like(f)
    for ch in range(3):
        bg = _background(img[:, :, ch]).astype(np.float32)
        norm = f[:, :, ch] / np.maximum(bg, 40.0) * 245.0            # clamped divisor -> no noise blow-up
        out[:, :, ch] = 0.75 * norm + 0.25 * f[:, :, ch]             # blend, keeps natural look
    img = np.clip(out, 0, 255).astype(np.uint8)
    img = _levels_L(img, 1, 99.5)               # global contrast; CLAHE here causes banding
    img = _saturate(img, 1.10)
    return _unsharp(img, 0.35, 1.2)


def _levels_L(bgr: np.ndarray, lo_pct: float, hi_pct: float) -> np.ndarray:
    lab = cv.cvtColor(bgr, cv.COLOR_BGR2LAB)
    L = lab[:, :, 0].astype(np.float32)
    lo, hi = np.percentile(L, lo_pct), np.percentile(L, hi_pct)
    lab[:, :, 0] = np.clip((L - lo) / max(1.0, hi - lo) * 252.0, 0, 255).astype(np.uint8)
    return cv.cvtColor(lab, cv.COLOR_LAB2BGR)


def filter_id_color(bgr: np.ndarray) -> np.ndarray:
    """'ID colour' (default in ID/Passport modes): no background whitening —
    a card is not white paper. Clean, sharp, true colours for colour copies."""
    img = _denoise(bgr)
    img = _gray_world_wb(img, 0.5)
    img = _clahe_L(img, 1.6)
    img = _saturate(img, 1.15)
    # gentle levels: stretch 1st..99th percentile of L
    lab = cv.cvtColor(img, cv.COLOR_BGR2LAB)
    L = lab[:, :, 0].astype(np.float32)
    lo, hi = np.percentile(L, 1), np.percentile(L, 99)
    lab[:, :, 0] = np.clip((L - lo) / max(1.0, hi - lo) * 250.0, 0, 255).astype(np.uint8)
    img = cv.cvtColor(lab, cv.COLOR_LAB2BGR)
    return _unsharp(img, 0.6, 1.0)


def filter_bw_print(bgr: np.ndarray) -> np.ndarray:
    """'B&W print': pure black text on white, for photocopies."""
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY)
    gray = cv.bilateralFilter(gray, 5, 30, 30)
    bg = _background(gray).astype(np.float32)
    norm = np.clip(gray.astype(np.float32) / np.maximum(bg, 40.0) * 255.0, 0, 255).astype(np.uint8)
    block = max(15, (min(gray.shape[:2]) // 40) | 1)
    bw = cv.adaptiveThreshold(norm, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 12)
    return cv.cvtColor(cv.medianBlur(bw, 3), cv.COLOR_GRAY2BGR)


def ocr_image(warped_bgr: np.ndarray) -> np.ndarray:
    """Dedicated image for ML Kit text recognition (never the user's filter)."""
    gray = cv.cvtColor(warped_bgr, cv.COLOR_BGR2GRAY)
    gray = cv.bilateralFilter(gray, 5, 30, 30)
    clahe = cv.createCLAHE(clipLimit=1.8, tileGridSize=(8, 8))
    return clahe.apply(gray)


# ---------------------------------------------------------------------------
# 4. Blur check (warn "Photo looks blurry — retake?")
# ---------------------------------------------------------------------------
def sharpness(bgr: np.ndarray) -> float:
    """Variance of Laplacian on a 1000-px copy. Below ~60 usually means blurry."""
    h, w = bgr.shape[:2]
    s = 1000.0 / max(h, w)
    g = cv.cvtColor(cv.resize(bgr, (int(w * s), int(h * s))), cv.COLOR_BGR2GRAY)
    return float(cv.Laplacian(g, cv.CV_64F).var())


# ---------------------------------------------------------------------------
# Demo runner
# ---------------------------------------------------------------------------
def _label(img, text):
    out = img.copy()
    cv.rectangle(out, (0, 0), (out.shape[1], 34), (0, 0, 0), -1)
    cv.putText(out, text, (8, 24), cv.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv.LINE_AA)
    return out


def _fit(img, h):
    return cv.resize(img, (int(img.shape[1] * h / img.shape[0]), h), interpolation=cv.INTER_AREA)


def run(in_dir: str, out_dir: str, mode_default: str = "document"):
    os.makedirs(out_dir, exist_ok=True)
    rows = []
    for p in sorted(glob.glob(os.path.join(in_dir, "*_photo.jpg"))):
        name = os.path.basename(p).replace("_photo.jpg", "")
        mode = "id" if name.startswith("id_") else mode_default
        img = cv.imread(p)
        q, score, src = detect_document(img, mode)
        found = q is not None
        if not found:
            q = fallback_quad(img.shape[1], img.shape[0])
        vis = img.copy()
        cv.polylines(vis, [q.astype(np.int32)], True, (0, 220, 0) if found else (0, 0, 255), 4)
        for x, y in q.astype(int):
            cv.circle(vis, (int(x), int(y)), 9, (255, 255, 255), -1)
        w = warp(img, q, mode)
        tiles = [_label(_fit(vis, 420), f"{name}: {'found' if found else 'NOT found'} ({src})"),
                 _label(_fit(w, 420), "Original (crop only)")]
        if mode == "id":
            tiles.append(_label(_fit(filter_id_color(w), 420), "ID colour"))
        else:
            tiles.append(_label(_fit(filter_auto_color(w), 420), "Auto (colour)"))
        tiles.append(_label(_fit(filter_bw_print(w), 420), "B&W print"))
        row = np.hstack([np.pad(t, ((6, 6), (6, 6), (0, 0)), constant_values=255) for t in tiles])
        rows.append(row)
        print(f"{name:16s} mode={mode:9s} found={found} score={score:.3f} via={src} sharpness={sharpness(img):.0f}")
    if rows:
        wmax = max(r.shape[1] for r in rows)
        rows = [np.pad(r, ((0, 0), (0, wmax - r.shape[1]), (0, 0)), constant_values=255) for r in rows]
        cv.imwrite(os.path.join(out_dir, "results.jpg"), np.vstack(rows), [cv.IMWRITE_JPEG_QUALITY, 88])


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode_arg = "document"
    if "--mode" in sys.argv:
        mode_arg = sys.argv[sys.argv.index("--mode") + 1]
    run(sys.argv[1], sys.argv[2], mode_arg)
