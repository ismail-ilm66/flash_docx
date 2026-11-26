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


def _edge_support(q: np.ndarray, gx: np.ndarray, gy: np.ndarray, mag: np.ndarray) -> tuple[float, float]:
    """How much of the quad's outline lies on a real edge in the photo.
    For each side, sample points (skipping the corners) and look up to 3 px across the
    side for a strong gradient that points ACROSS the side. Returns (mean, min) of the
    four sides' support, 0..1. Sides running along the photo border, across a table or
    through the middle of a sheet get ~0; a real page edge gets ~0.6-1."""
    h, w = mag.shape
    thr = max(12.0, float(np.percentile(mag, 75)))
    sides = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        d = b - a
        L = float(np.linalg.norm(d))
        if L < 8:
            sides.append(0.0); continue
        t = d / L
        n = np.array([-t[1], t[0]])
        hits = tot = 0
        for f in np.linspace(0.08, 0.92, 40):
            p = a + d * f
            tot += 1
            for off in (0, -1, 1, -2, 2, -3, 3):
                x, y = int(round(p[0] + n[0] * off)), int(round(p[1] + n[1] * off))
                if 0 <= x < w and 0 <= y < h and mag[y, x] > thr:
                    g = np.array([gx[y, x], gy[y, x]]) / (mag[y, x] + 1e-6)
                    if abs(float(np.dot(g, n))) > 0.75:
                        hits += 1
                        break
        sides.append(hits / max(1, tot))
    return float(np.mean(sides)), float(min(sides))


def _line_quads(c: np.ndarray, w: int, h: int, max_lines: int = 9):
    """Quads made from 4 straight stretches of a region's outline, extended until they
    meet. Finds the page when its region is merged with another paper behind it (one
    corner hidden or stuck to the other sheet): the page's sides are still straight
    stretches of the outline even though the outline as a whole is not a quad."""
    peri = cv.arcLength(c, True)
    poly = cv.approxPolyDP(c, 0.01 * peri, True).reshape(-1, 2).astype(np.float32)
    n = len(poly)
    if n < 4:
        return []
    segs = []
    min_len = 0.10 * min(w, h)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        L = float(np.linalg.norm(b - a))
        if L >= min_len:
            segs.append((i, a, b, L))
    segs = sorted(segs, key=lambda s: -s[3])[:max_lines]
    segs = sorted(segs, key=lambda s: s[0])          # keep outline order
    if len(segs) < 4:
        return []

    def inter(s1, s2):
        p, r = s1[1], s1[2] - s1[1]
        q2, t2 = s2[1], s2[2] - s2[1]
        den = r[0] * t2[1] - r[1] * t2[0]
        if abs(den) < 1e-6:
            return None
        u = ((q2[0] - p[0]) * t2[1] - (q2[1] - p[1]) * t2[0]) / den
        return p + u * r

    out = []
    from itertools import combinations
    mx, my = 0.04 * w, 0.04 * h
    for combo in combinations(range(len(segs)), 4):
        ss = [segs[k] for k in combo]
        pts = []
        ok = True
        for k in range(4):
            pt = inter(ss[k], ss[(k + 1) % 4])
            if pt is None or not (-mx <= pt[0] <= w - 1 + mx and -my <= pt[1] <= h - 1 + my):
                ok = False; break
            pts.append(pt)
        if not ok:
            continue
        qq = np.array(pts, np.float32)
        if not cv.isContourConvex(qq.reshape(-1, 1, 2)):
            continue
        qq[:, 0] = np.clip(qq[:, 0], 0, w - 1)
        qq[:, 1] = np.clip(qq[:, 1], 0, h - 1)
        out.append(qq)
    return out


def _side_contrast(q: np.ndarray, lab: np.ndarray, off: int = 8) -> float:
    """Mean colour difference (Lab, 0..1 after /20) between just inside and just outside
    the quad's sides. A real page edge separates paper from something else; a printed
    rule or table line inside the page has paper on both sides (round 11)."""
    h, w = lab.shape[:2]
    cxy = q.mean(axis=0)
    vals = []
    for i in range(4):
        a, b = q[i], q[(i + 1) % 4]
        d = b - a
        L = float(np.linalg.norm(d))
        if L < 8:
            vals.append(0.0); continue
        n = np.array([-d[1], d[0]]) / L
        if np.dot(cxy - (a + b) / 2, n) < 0:       # make n point inwards
            n = -n
        ins, outs = [], []
        for f in np.linspace(0.1, 0.9, 25):
            p = a + d * f
            pi, po = p + n * off, p - n * off
            xi, yi, xo, yo = int(pi[0]), int(pi[1]), int(po[0]), int(po[1])
            if 0 <= xi < w and 0 <= yi < h and 0 <= xo < w and 0 <= yo < h:
                ins.append(lab[yi, xi]); outs.append(lab[yo, xo])
        if len(ins) < 5:
            vals.append(0.0); continue            # side on the photo border: unknown
        diff = np.abs(np.array(ins, np.float32) - np.array(outs, np.float32))
        de = float(np.median(np.sqrt((diff ** 2).sum(1))))
        vals.append(min(1.0, de / 20.0))
    return float(np.mean(vals))


def _hough_quads(gray_u8: np.ndarray, w: int, h: int, max_per_group: int = 6):
    """Quads from the longest straight lines in the photo (2 roughly horizontal + 2
    roughly vertical, extended until they meet). Round 11: finds a white page lying on a
    pale folder or sheet, where every brightness/colour map merges page and folder into
    one area but the page's own edges are still clear straight lines."""
    edges = cv.Canny(gray_u8, 40, 120)
    L = cv.HoughLinesP(edges, 1, np.pi / 180, 60, minLineLength=int(0.25 * min(w, h)), maxLineGap=15)
    if L is None:
        return []
    hor, ver = [], []
    for x1, y1, x2, y2 in L.reshape(-1, 4).astype(np.float32):
        ang = np.degrees(np.arctan2(y2 - y1, x2 - x1)) % 180
        seg = (np.array([x1, y1]), np.array([x2, y2]), float(np.hypot(x2 - x1, y2 - y1)), ang)
        if ang < 35 or ang > 145:
            hor.append(seg)
        elif 55 < ang < 125:
            ver.append(seg)

    def merge(group, horizontal):
        # keep the longest line of each "track" (lines closer than 2% are the same edge)
        group = sorted(group, key=lambda g: -g[2])
        out = []
        for g in group:
            mid = (g[0] + g[1]) / 2
            pos = mid[1] if horizontal else mid[0]
            if all(abs(pos - ((o[0] + o[1]) / 2)[1 if horizontal else 0]) > 0.02 * (h if horizontal else w) for o in out):
                out.append(g)
            if len(out) >= max_per_group:
                break
        return out

    hor, ver = merge(hor, True), merge(ver, False)
    if len(hor) < 2 or len(ver) < 2:
        return []

    def inter(a, b):
        p, r = a[0], a[1] - a[0]
        q, t = b[0], b[1] - b[0]
        den = r[0] * t[1] - r[1] * t[0]
        if abs(den) < 1e-6:
            return None
        u = ((q[0] - p[0]) * t[1] - (q[1] - p[1]) * t[0]) / den
        return p + u * r

    from itertools import combinations
    out = []
    mx, my = 0.04 * w, 0.04 * h
    for t1, t2 in combinations(hor, 2):
        top, bot = (t1, t2) if (t1[0][1] + t1[1][1]) < (t2[0][1] + t2[1][1]) else (t2, t1)
        for v1, v2 in combinations(ver, 2):
            lef, rig = (v1, v2) if (v1[0][0] + v1[1][0]) < (v2[0][0] + v2[1][0]) else (v2, v1)
            pts = [inter(top, lef), inter(top, rig), inter(bot, rig), inter(bot, lef)]
            if any(p is None or not (-mx <= p[0] <= w - 1 + mx and -my <= p[1] <= h - 1 + my) for p in pts):
                continue
            q = np.array(pts, np.float32)
            if not cv.isContourConvex(q.reshape(-1, 1, 2)):
                continue
            q[:, 0] = np.clip(q[:, 0], 0, w - 1)
            q[:, 1] = np.clip(q[:, 1], 0, h - 1)
            out.append(q)
    return out


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
    # D) Smooth regions: on busy backgrounds (patterned cloth, wood grain) the page is
    # the big area with almost no edges. Invert the edge map and open it so thin gaps
    # in the pattern disappear and the page remains as one blob.
    smooth = cv.bitwise_not(edges)
    k3 = cv.getStructuringElement(cv.MORPH_RECT, (15, 15))
    smooth = cv.morphologyEx(smooth, cv.MORPH_OPEN, k3)
    smooth = cv.dilate(smooth, k, iterations=1)   # give back the rim eaten by the edge dilation
    maps.append(("smooth", smooth))
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

    # E) Smooth AND pale: on a busy, colourful background (patterned cloth) the page is
    # the only area that is both smooth and low-saturation/bright. Blurry background
    # areas are smooth but coloured, so the AND removes them.
    smooth_map = dict(maps)["smooth"]
    for name, pale in (("smooth+lowsat", ts), ("smooth+bright", th)):
        combo = cv.bitwise_and(smooth_map, pale)
        # A strong opening (≈ 5% of the short side) cuts thin bridges between the page
        # and pale patches of background; the page itself is far wider and survives.
        ko = max(15, (min(small.shape[:2]) // 10) | 1)
        kbig = cv.getStructuringElement(cv.MORPH_ELLIPSE, (ko, ko))
        combo = cv.morphologyEx(combo, cv.MORPH_OPEN, kbig)
        combo = cv.morphologyEx(combo, cv.MORPH_CLOSE, k2, iterations=2)
        maps.append((name, combo))
    return maps


def page_fills_frame(bgr: np.ndarray, imported: bool = False) -> bool:
    """True when the page already fills the photo: an image that was cropped before it
    was imported, or a page photographed so close that its edges are outside the photo.
    Then the whole image is the page; running the detector only finds lines INSIDE the
    page (a header box, a table) and crops wrongly (round 11).

    Test: a 3% strip along each side; a side is 'paper' when 60%+ of the strip is bright
    (> 72% of the image's 90th-percentile brightness) and unsaturated (S < 60).
    Imports need 2 paper sides, camera photos 3. Tested: 17 of 18 already-cropped pages
    and 0 of 14 photos of pages on tables, cloth, folders or in a hand."""
    s = 800.0 / max(bgr.shape[:2])
    im = cv.resize(bgr, None, fx=s, fy=s, interpolation=cv.INTER_AREA) if s < 1 else bgr
    hsv = cv.cvtColor(im, cv.COLOR_BGR2HSV)
    V, S = hsv[:, :, 2].astype(np.float32), hsv[:, :, 1]
    paper = (V > 0.72 * np.percentile(V, 90)) & (S < 60)
    h, w = paper.shape
    b = max(3, int(0.03 * min(h, w)))
    sides = [paper[:b, :].mean(), paper[-b:, :].mean(), paper[:, :b].mean(), paper[:, -b:].mean()]
    return sum(v >= 0.6 for v in sides) >= (2 if imported else 3)


def detect_document(bgr: np.ndarray, mode: str = "document", imported: bool = False):
    """
    Returns (corners TL,TR,BR,BL in full-resolution pixel coords, score, source)
    or (None, 0, None) when nothing convincing is found.
    `imported`: True for images picked from the gallery/files or shared into the app.
    """
    H, W = bgr.shape[:2]
    if mode == "document" and page_fills_frame(bgr, imported):
        full = np.array([[0, 0], [W - 1, 0], [W - 1, H - 1], [0, H - 1]], np.float32)
        return full, 1.0, "fills-frame"
    scale = DETECT_LONG_EDGE / max(H, W)
    small = cv.resize(bgr, (int(W * scale), int(H * scale)), interpolation=cv.INTER_AREA) if scale < 1 else bgr.copy()
    if scale >= 1:
        scale = 1.0
    h, w = small.shape[:2]
    img_area = float(h * w)

    target = {"id": ID_ASPECT, "passport": PASSPORT_ASPECT}.get(mode)
    best, best_score, best_src = None, 0.0, None

    gray = cv.GaussianBlur(cv.cvtColor(small, cv.COLOR_BGR2GRAY), (5, 5), 0).astype(np.float32)
    gx, gy = cv.Sobel(gray, cv.CV_32F, 1, 0), cv.Sobel(gray, cv.CV_32F, 0, 1)
    mag = cv.magnitude(gx, gy)

    found = []
    lab_small = cv.cvtColor(cv.GaussianBlur(small, (5, 5), 0), cv.COLOR_BGR2LAB).astype(np.float32)
    maps = _candidate_maps(small)
    # Straight-line quads (round 11), scored against the "paper-like" area (bright OR pale).
    md = dict(maps)
    paper = cv.bitwise_or(md.get("bright", np.zeros((h, w), np.uint8)), md.get("lowsat", np.zeros((h, w), np.uint8)))
    for q in _hough_quads(cv.GaussianBlur(cv.cvtColor(small, cv.COLOR_BGR2GRAY), (5, 5), 0), w, h):
        q = _order_corners(q)
        qa = cv.contourArea(q)
        frac = qa / img_area
        if frac > 0.98 or frac < MIN_AREA_FRAC:
            continue
        rect = _corner_angles_score(q)
        if rect < 0.55:
            continue
        m = 0.02 * max(w, h)
        on_border = sum(1 for x, y in q if x < m or y < m or x > w - 1 - m or y > h - 1 - m)
        qm = np.zeros((h, w), np.uint8)
        cv.fillConvexPoly(qm, q.astype(np.int32), 255)
        cover = float(cv.countNonZero(cv.bitwise_and(qm, paper))) / max(1.0, float(cv.countNonZero(qm)))
        pre = frac ** 0.5 * rect * cover ** 2
        if target:
            pre *= max(0.05, 1.0 - abs(_aspect(q) - target) / target * 2.5)
        found.append((pre, q, on_border, frac, "hough/lines"))

    for name, bmap in maps:
        retr = cv.RETR_LIST if name == "edges" else cv.RETR_EXTERNAL
        contours, _ = cv.findContours(bmap, retr, cv.CHAIN_APPROX_SIMPLE)
        for c in contours:
            area = cv.contourArea(c)
            if area < MIN_AREA_FRAC * img_area:
                continue
            cands = []
            q0 = _quad_from_contour(c)
            if q0 is not None:
                cands.append(("hull", q0))
            # Region merged with something else (another sheet, a pale table corner):
            # also try quads built from straight stretches of its outline.
            if name != "edges":
                cands += [("lines", qq) for qq in _line_quads(c, w, h)]
            if not cands:
                continue
            region = np.zeros((h, w), np.uint8)
            cv.drawContours(region, [c], -1, 255, -1)
            for kind, q in cands:
                q = _order_corners(q)
                if name != "edges" and kind == "hull":
                    # Round 8: no longer pushed 2% outward. That pulled a strip of table
                    # into the crop, which printed as black lines. A crop a hair inside
                    # the paper is invisible; one outside is not. clean_page_border()
                    # removes any sliver that is left.
                    cxy = q.mean(axis=0)
                    q = cxy + (q - cxy) * 1.0
                    q[:, 0] = np.clip(q[:, 0], 0, w - 1)
                    q[:, 1] = np.clip(q[:, 1], 0, h - 1)
                qa = cv.contourArea(q)
                frac = qa / img_area
                if frac > 0.98 or frac < MIN_AREA_FRAC:   # the photo border / too small
                    continue
                # Corners hugging the photo border (checked again below).
                m = 0.02 * max(w, h)
                on_border = sum(1 for x, y in q if x < m or y < m or x > w - 1 - m or y > h - 1 - m)
                rect = _corner_angles_score(q)
                if rect < 0.55:
                    continue
                # How much of the quad is covered by the region (a quad that also takes in
                # table or a second sheet is only partly covered).
                qm = np.zeros((h, w), np.uint8)
                cv.fillConvexPoly(qm, q.astype(np.int32), 255)
                cover = float(cv.countNonZero(cv.bitwise_and(qm, region))) / max(1.0, float(cv.countNonZero(qm)))
                if name == "edges":
                    cover = min(1.0, area / max(1.0, qa))
                pre = frac ** 0.5 * rect * cover ** 2
                if name == "edges":
                    pre *= 0.45 ** on_border   # the edge map has an artificial border line
                if target:
                    pre *= max(0.05, 1.0 - abs(_aspect(q) - target) / target * 2.5)
                found.append((pre, q, on_border, frac, f"{name}/{kind}"))

    # Edge support is the expensive part: only check the 16 best candidates.
    for pre, q, on_border, frac, src in sorted(found, key=lambda t: -t[0])[:16]:
        sup_mean, sup_min = _edge_support(q, gx, gy, mag)
        # 3+ corners on the border is usually the photo frame itself. Keep it only when it
        # is clearly smaller than the frame AND its outline follows real edges (a page
        # photographed close up, running off one side).
        if on_border >= 3 and (frac > 0.90 or sup_mean < 0.45):
            continue
        score = pre * (0.25 + 0.75 * sup_mean) * (0.6 + 0.4 * sup_min)
        # Straight-line quads must also SEPARATE paper from something else on each side
        # (not follow a printed line inside the page).
        if src.startswith("hough"):
            score *= 0.3 + 0.7 * _side_contrast(q, lab_small)
        if DET_DEBUG:
            print(f"    {src:22s} frac={frac:.2f} pre={pre:.3f} sup={sup_mean:.2f}/{sup_min:.2f} border={on_border} -> {score:.3f}")
        if score > best_score:
            best, best_score, best_src = q, score, src

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
# 1b. LIVE outline for the camera preview (round 11b)
#     Same detector as the captured photo, but on a SMALL colour frame (long side 320).
#     Tested on all 16 test photos: same page as the full-size detection (overlap 0.92-0.99),
#     ~70 ms per frame in Python. Running it on full camera frames is what made the live
#     outline slow and the whole app sluggish on the Tecno KC2.
#     Frame -> small BGR: take the YUV420 frame, scale Y to 320 long side and the U/V planes
#     to the same size, convert YUV->BGR (cheap at this size). One frame in flight at a time.
# ---------------------------------------------------------------------------
LIVE_SIZE = 320


def detect_live(small_bgr: np.ndarray, mode: str = "document"):
    """small_bgr: camera frame already scaled to LIVE_SIZE long side (do the scaling while
    converting from YUV, never on the full frame). Returns corners in small_bgr coordinates
    or None. Scale them to preview coordinates in the UI."""
    h, w = small_bgr.shape[:2]
    if max(h, w) > LIVE_SIZE + 8:
        s = LIVE_SIZE / float(max(h, w))
        small_bgr = cv.resize(small_bgr, (int(w * s), int(h * s)), interpolation=cv.INTER_AREA)
    else:
        s = 1.0
    q, score, _ = detect_document(small_bgr, mode)
    if q is None or score <= 0:
        return None
    return q / s


class LiveOutline:
    """Smoothing + stability for the camera outline and auto capture (round 11b).
    Call update(quad_or_None, t_seconds, phone_still) for every analysed frame.
    - outline: corners moved 30% towards each new detection (no shaking)
    - shown only after 2 frames in a row with a page; hidden after 4 frames without
    - 'stable' when every corner stayed within 2% of the frame diagonal for 0.8 s and the
      phone is still; a small wobble (2-5%) PAUSES the timer instead of restarting it;
      only a real move (> 5%) or losing the page restarts it."""
    def __init__(self, frame_w, frame_h, hold=0.8):
        self.diag = float(np.hypot(frame_w, frame_h))
        self.hold = hold
        self.q = None
        self.hits = 0
        self.miss = 0
        self.anchor = None
        self.t_still = 0.0
        self.t_pause = 0.0
        self.t_last = None

    def update(self, quad, t, phone_still=True):
        dt = 0.0 if self.t_last is None else max(0.0, t - self.t_last)
        self.t_last = t
        if quad is None:
            self.miss += 1
            self.hits = 0
            if self.miss >= 4:
                self.q, self.anchor, self.t_still = None, None, 0.0
            return self.state()
        self.miss = 0
        self.hits += 1
        quad = np.asarray(quad, np.float32)
        self.q = quad if self.q is None else self.q + 0.3 * (quad - self.q)
        if self.anchor is None:
            self.anchor, self.t_still = self.q.copy(), 0.0
            return self.state()
        move = float(np.max(np.linalg.norm(self.q - self.anchor, axis=1))) / self.diag
        if move > 0.05:                               # real move: start again
            self.anchor, self.t_still, self.t_pause = self.q.copy(), 0.0, 0.0
        elif move <= 0.02 and phone_still:
            self.t_still += dt                        # steady: count up
            self.t_pause = 0.0
        else:
            # 0.02..0.05 or phone moving: pause (keep the time already counted) ...
            self.t_pause += dt
            if self.t_pause > 0.4 and phone_still:    # ... but a lasting offset is a new spot
                self.anchor, self.t_still, self.t_pause = self.q.copy(), 0.0, 0.0
        return self.state()

    def state(self):
        shown = self.q is not None and (self.hits >= 2 or self.miss > 0)
        progress = 0.0 if not shown else min(1.0, self.t_still / self.hold)
        return {"outline": self.q if shown else None, "progress": progress, "capture": progress >= 1.0}


# ---------------------------------------------------------------------------
# 2b. Bent page flattening (round 11b)
#     A card or receipt held in the hand bends, so its edges are curves, not
#     straight lines. After the normal 4-corner crop, trace the real page edges,
#     fit a smooth curve to each side and stretch them straight (Coons patch).
#     One cv.remap straight from the ORIGINAL photo -> no double blur.
#     Document mode only (ID / passport cards are stiff). Skips itself when the
#     edges are already straight or can't be traced reliably.
# ---------------------------------------------------------------------------
CURVE_MARGIN = 0.20        # look this far outside the 4-corner crop for the real edge
CURVE_MIN_DEV = 0.004      # bend smaller than 0.4% of the page -> nothing to do
CURVE_MAX_DEV = 0.10       # bend bigger than 10% of the page -> that side's tracing is unreliable: keep it straight
CURVE_MAX_CORNER = 0.18    # a corner may move up to 18% of the page (fixes a detector corner that sits
                           # inside the page) - only when the traced side is clean (see CURVE_MIN_INLIERS)
CURVE_MIN_INLIERS = 0.7    # share of traced points that must agree with the fitted side
CURVE_MAX_RMS = 2.0        # and their average distance from it (small-copy pixels)
CURVE_MAX_INWARD = 0.03    # inwards (into the page) at most 3%: a coloured band along the page edge
                           # looks like 'not paper' and must never get cropped off
CURVE_MIN_VALID = 0.5      # at least half of each side must be traced
CURVE_DEBUG = False


def _skin_mask(bgr: np.ndarray) -> np.ndarray:
    """Skin-coloured pixels (any skin tone; YCrCb rule)."""
    ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb)
    Y, Cr, Cb = cv.split(ycc)
    m = ((Cr >= 135) & (Cr <= 180) & (Cb >= 77) & (Cb <= 127) & (Y > 50)).astype(np.uint8) * 255
    m = cv.morphologyEx(m, cv.MORPH_OPEN, np.ones((5, 5), np.uint8))
    return cv.morphologyEx(m, cv.MORPH_CLOSE, np.ones((15, 15), np.uint8))


def _fit_side(u: np.ndarray, e: np.ndarray, pinned: bool = False):
    """One side of the page: e(u) = c0 + c1*u + u(1-u)(c2 + c3*u), u in 0..1, e = pixels outwards
    from the straight crop line. c0 / c0+c1 move the two corners, c2/c3 bend the middle.
    pinned=True keeps both corners where the detector put them (c0 = c1 = 0).
    Least squares, refit twice without outliers (finger, text, background leaks).
    Dart: 4x4 (or 2x2) normal equations solved by hand; no library needed."""
    cols = [u * (1 - u), u * u * (1 - u)] if pinned else [np.ones_like(u), u, u * (1 - u), u * u * (1 - u)]
    A = np.stack(cols, 1)
    keep = np.ones(len(u), bool)
    c = None
    for _ in range(3):
        if keep.sum() < 8:
            return None
        c, *_ = np.linalg.lstsq(A[keep], e[keep], rcond=None)
        r = np.abs(A @ c - e)
        mad = np.median(r[keep]) + 1e-6
        keep = r < max(1.5, 3.0 * mad)
    if keep.sum() < 8:
        return None
    rms = float(np.sqrt(np.mean((A[keep] @ c - e[keep]) ** 2)))
    c = np.concatenate([[0.0, 0.0], c]) if pinned else c
    return c, float(keep.mean()), rms


def _side_e(c, u):
    return c[0] + c[1] * u + u * (1 - u) * (c[2] + c[3] * u)


def _bend_only(c, u):
    return u * (1 - u) * (c[2] + c[3] * u)


def warp_curved(bgr: np.ndarray, q: np.ndarray, mode: str = "document", corners_fixed: bool = False) -> np.ndarray:
    """Drop-in replacement for warp() in Document mode. Falls back to warp() when not needed.
    Traces the real page edges just outside/inside the 4-corner crop, bends each side to match
    and may move a detected corner OUTWARDS onto the real page corner (never into the page).
    corners_fixed=True when the user dragged the corners in Adjust edges: their corners are
    kept exactly, only the sides may bend."""
    if mode != "document":
        return warp(bgr, q, mode)
    q = _order_corners(q).astype(np.float32)
    Wt = int(max(np.linalg.norm(q[2] - q[3]), np.linalg.norm(q[1] - q[0])))
    Ht = int(max(np.linalg.norm(q[1] - q[2]), np.linalg.norm(q[0] - q[3])))
    # Trace on a small copy (long side 800); the final remap is full size.
    s = min(1.0, 800.0 / max(Wt, Ht))
    w, h = max(16, int(Wt * s)), max(16, int(Ht * s))
    mx, my = int(w * CURVE_MARGIN) + 2, int(h * CURVE_MARGIN) + 2
    dst = np.array([[mx, my], [mx + w - 1, my], [mx + w - 1, my + h - 1], [mx, my + h - 1]], np.float32)
    Hm = cv.getPerspectiveTransform(q, dst)
    size = (w + 2 * mx, h + 2 * my)
    small = cv.warpPerspective(bgr, Hm, size, flags=cv.INTER_AREA, borderMode=cv.BORDER_CONSTANT, borderValue=(0, 0, 0))
    valid = cv.warpPerspective(np.full(bgr.shape[:2], 255, np.uint8), Hm, size, flags=cv.INTER_NEAREST)

    # Paper mask: close to the paper colour measured in the middle of the page,
    # text holes closed, then only the region that holds the page centre.
    lab = cv.cvtColor(small, cv.COLOR_BGR2LAB).astype(np.float32)
    centre = lab[my + h // 5:my + 4 * h // 5, mx + w // 5:mx + 4 * w // 5].reshape(-1, 3)
    centre = centre[centre[:, 0] >= np.percentile(centre[:, 0], 60)]
    Lp, ap, bp = np.median(centre, axis=0)
    dist = np.sqrt(((lab[..., 0] - Lp) * 0.5) ** 2 + (lab[..., 1] - ap) ** 2 + (lab[..., 2] - bp) ** 2)
    paper = ((dist < 18) & (lab[..., 0] > Lp - 30) & (valid > 0)).astype(np.uint8) * 255
    k = max(3, int(0.03 * min(w, h)) | 1)
    paper = cv.morphologyEx(paper, cv.MORPH_CLOSE, cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k)))
    n, lbl, st, _ = cv.connectedComponentsWithStats(paper)
    # The page = the paper region that covers most of the page's middle (not one centre pixel:
    # that pixel is often on text and then belongs to no region).
    mid = lbl[my + h // 4:my + 3 * h // 4, mx + w // 4:mx + 3 * w // 4]
    counts = np.bincount(mid.ravel(), minlength=n)
    counts[0] = 0
    c_lbl = int(np.argmax(counts))
    if counts[c_lbl] < 0.3 * mid.size:
        return warp(bgr, q, mode)
    page = (lbl == c_lbl)
    skin = cv.dilate(_skin_mask(small), np.ones((9, 9), np.uint8)) > 0   # fingers hide the edge there

    def side(name):
        """Bend of one side in small-warp pixels (+ = outwards), or None."""
        horiz = name in ("top", "bottom")
        length = w if horiz else h
        start = mx if horiz else my
        straight = {"top": my, "bottom": my + h - 1, "left": mx, "right": mx + w - 1}[name]
        reach = int(CURVE_MAX_CORNER * (h if horiz else w)) + 3   # search this far in and out
        out_dir = -1 if name in ("top", "left") else 1
        us, es = [], []
        step = max(1, length // 120)
        for t in range(start + length // 20, start + length - length // 20, step):
            e = None
            # walk from outside towards the page; the first paper pixel is the edge
            for d in range(reach, -reach - 1, -1):
                i = straight + out_dir * d
                y, x = (i, t) if horiz else (t, i)
                if not (0 <= y < size[1] and 0 <= x < size[0]) or not valid[y, x]:
                    continue
                if page[y, x]:
                    e = d
                    break
            if e is None or e == reach:          # edge not seen / page runs past the search
                continue
            y, x = (straight + out_dir * e, t) if horiz else (t, straight + out_dir * e)
            if skin[max(0, y - 4):y + 5, max(0, x - 4):x + 5].any():
                continue
            us.append((t - start) / (length - 1)); es.append(e)
        if len(us) < CURVE_MIN_VALID * (length * 0.9) / step:
            return None
        other = h if horiz else w
        U, E = np.array(us), np.array(es, np.float64)
        r = _fit_side(U, E, pinned=corners_fixed)
        if r is None:
            return None
        c, inl, rms = r
        lo_c = min(c[0], c[0] + c[1])
        if (max(c[0], c[0] + c[1]) > CURVE_MAX_CORNER * other or lo_c < -CURVE_MAX_INWARD * other
                or inl < CURVE_MIN_INLIERS or rms > CURVE_MAX_RMS):
            r = _fit_side(U, E, pinned=True)     # not clean enough to move corners: keep the detector's
            if r is None or r[1] < CURVE_MIN_INLIERS or r[2] > CURVE_MAX_RMS:
                return None                      # still not clean: keep this side straight
            c = r[0]
        tt = np.linspace(0, 1, 50)
        peak = float(np.max(np.abs(_bend_only(c, tt))))
        if peak > CURVE_MAX_DEV * other:
            return None                          # unreliable: keep this side straight
        if float(np.min(_side_e(c, tt))) < -CURVE_MAX_INWARD * other:
            return None                          # would cut into the page: keep this side straight
        change = max(peak, abs(c[0]), abs(c[0] + c[1]))
        return c, change

    bends, peaks = {}, []
    for name in ("top", "bottom", "left", "right"):
        r = side(name)
        bends[name] = r[0] if r else np.zeros(4)
        rel = (r[1] / (h if name in ("top", "bottom") else w)) if r else 0.0
        peaks.append(rel)
    if CURVE_DEBUG:
        print("    side change (fraction of page):", [round(p, 4) for p in peaks])
    if max(peaks) < CURVE_MIN_DEV:
        return warp(bgr, q, mode)

    # Corners (each may have moved a little outwards/inwards) and the 4 curves through them.
    x0, x1, y0, y1 = mx, mx + w - 1, my, my + h - 1
    eT, eB, eL, eR = (lambda t, n=n: _side_e(bends[n], t) for n in ("top", "bottom", "left", "right"))
    TL = np.array([x0 - eL(0.0), y0 - eT(0.0)]); TR = np.array([x1 + eR(0.0), y0 - eT(1.0)])
    BL = np.array([x0 - eL(1.0), y1 + eB(0.0)]); BR = np.array([x1 + eR(1.0), y1 + eB(1.0)])

    # Output size from the curve lengths, at full resolution.
    def arclen(xs, ys):
        return float(np.sum(np.hypot(np.diff(xs), np.diff(ys))))
    t = np.linspace(0, 1, 100)
    Wo = int(round(max(arclen(TL[0] + t * (TR[0] - TL[0]), y0 - eT(t)), arclen(BL[0] + t * (BR[0] - BL[0]), y1 + eB(t))) / s))
    Ho = int(round(max(arclen(x0 - eL(t), TL[1] + t * (BL[1] - TL[1])), arclen(x1 + eR(t), TR[1] + t * (BR[1] - TR[1]))) / s))

    # Coons patch on a coarse grid (every 8 px of output), then resized to full maps -> fast.
    gw, gh = max(2, Wo // 8), max(2, Ho // 8)
    u = np.linspace(0, 1, gw)[None, :]; v = np.linspace(0, 1, gh)[:, None]
    tx, ty = TL[0] + u * (TR[0] - TL[0]), y0 - eT(u)
    bx, by = BL[0] + u * (BR[0] - BL[0]), y1 + eB(u)
    lx, ly = x0 - eL(v), TL[1] + v * (BL[1] - TL[1])
    rx, ry = x1 + eR(v), TR[1] + v * (BR[1] - TR[1])
    X = (1 - v) * tx + v * bx + (1 - u) * lx + u * rx - ((1 - u) * (1 - v) * TL[0] + u * (1 - v) * TR[0] + (1 - u) * v * BL[0] + u * v * BR[0])
    Y = (1 - v) * ty + v * by + (1 - u) * ly + u * ry - ((1 - u) * (1 - v) * TL[1] + u * (1 - v) * TR[1] + (1 - u) * v * BL[1] + u * v * BR[1])
    # Small warped space -> original photo coordinates (one interpolation in total).
    Hi = np.linalg.inv(Hm)
    P = np.stack([X, Y, np.ones_like(X)], -1) @ Hi.T
    mapx = cv.resize((P[..., 0] / P[..., 2]).astype(np.float32), (Wo, Ho), interpolation=cv.INTER_LINEAR)
    mapy = cv.resize((P[..., 1] / P[..., 2]).astype(np.float32), (Wo, Ho), interpolation=cv.INTER_LINEAR)
    return cv.remap(bgr, mapx, mapy, cv.INTER_CUBIC, borderMode=cv.BORDER_REPLICATE)


# ---------------------------------------------------------------------------
# 2c. Finger removal (round 11b)
#     Fingers holding the page come in from its edge. find_fingers() runs on the
#     cropped COLOUR page (before any filter); the app shows the result as a thin
#     amber outline + "Fingers found · Remove". remove_fingers() runs only when the
#     user taps Remove, on the FILTERED page, with the same mask.
# ---------------------------------------------------------------------------
FINGER_MIN_AREA = 0.002    # of the page
FINGER_MAX_AREA = 0.20
FINGER_MAX_SKIN = 0.25     # more skin than this -> the paper itself is skin-coloured: don't suggest
FINGER_MAX_SPAN = 0.5      # touches at most half of the side it comes in from
FINGER_MIN_DEPTH = 0.03    # reaches at least 3% of the short side into the page
FINGER_MIN_DE = 12.0       # colour distance from the paper (Lab)
FINGER_MIN_RED = 8.0       # skin is redder than paper (Lab a*), cream paper in warm light is not
FINGER_MAX_RED = 35.0      # deep red cloth / print is not skin


def find_fingers(page_bgr: np.ndarray) -> np.ndarray | None:
    """Mask (uint8 0/255, page size) of fingers entering the page from its edge, or None.
    A region counts only if it is
      - skin-coloured (YCrCb rule) and clearly redder than the paper (Lab a*), not deep red cloth,
      - clearly different from the paper colour (cream paper in warm light passes the skin rule),
      - entering from one edge like a finger: touching it along at most half that side and
        reaching into the page (not a thin band along the border)."""
    H, W = page_bgr.shape[:2]
    s = min(1.0, 1000.0 / max(H, W))
    small = cv.resize(page_bgr, (int(W * s), int(H * s)), interpolation=cv.INTER_AREA) if s < 1 else page_bgr
    h, w = small.shape[:2]
    skin = _skin_mask(small)
    if cv.countNonZero(skin) > FINGER_MAX_SKIN * h * w:
        return None
    lab = cv.cvtColor(small, cv.COLOR_BGR2LAB).astype(np.float32)
    centre = lab[h // 5:4 * h // 5, w // 5:4 * w // 5].reshape(-1, 3)
    centre = centre[centre[:, 0] >= np.percentile(centre[:, 0], 60)]
    Lp, ap, bp = np.median(centre, axis=0)                 # paper colour
    n, lbl, st, _ = cv.connectedComponentsWithStats(skin)
    out = np.zeros((h, w), np.uint8)
    m = 4
    short = min(h, w)
    for i in range(1, n):
        x, y, bw, bh, a = st[i]
        if not (FINGER_MIN_AREA * h * w < a < FINGER_MAX_AREA * h * w):
            continue
        comp = (lbl == i)
        # which edge does it come in from, how wide is the contact, how deep does it reach?
        touch = {"top": comp[:m, :].any(0), "bottom": comp[-m:, :].any(0),
                 "left": comp[:, :m].any(1), "right": comp[:, -m:].any(1)}
        edge = max(touch, key=lambda k: touch[k].sum())
        span = touch[edge].sum() / float(len(touch[edge]))
        if touch[edge].sum() < 0.02 * short:                # must really enter from the edge
            continue
        if span > FINGER_MAX_SPAN:                          # a band along the whole border
            continue
        depth = {"top": y + bh, "bottom": h - y, "left": x + bw, "right": w - x}[edge]
        if depth < FINGER_MIN_DEPTH * short:
            continue
        L_, a_, b_ = lab[comp].mean(axis=0)
        dE = float(np.sqrt((L_ - Lp) ** 2 + (a_ - ap) ** 2 + (b_ - bp) ** 2))
        # 8-bit Lab (OpenCV and opencv_dart): a* is stored +128
        if dE < FINGER_MIN_DE or (a_ - ap) < FINGER_MIN_RED or (a_ - 128.0) > FINGER_MAX_RED:
            continue
        out[comp] = 255
    if not out.any():
        return None
    cnts, _ = cv.findContours(out, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE)
    cv.drawContours(out, cnts, -1, 255, -1)    # fill nail / shading holes
    k = max(5, int(0.02 * short) | 1)          # grow over the soft edge and the finger's shadow
    out = cv.dilate(out, cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k)))
    return cv.resize(out, (W, H), interpolation=cv.INTER_LINEAR) if s < 1 else out


def finger_outline(mask: np.ndarray):
    """Contours for the amber outline on screen (draw 1.5 dp, same amber as the camera outline)."""
    cnts, _ = cv.findContours((mask > 127).astype(np.uint8), cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE)
    return cnts


def remove_fingers(page_bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Fill the mask with the paper colour around it, soft-blended. Works on any filter's output."""
    m = (mask > 127).astype(np.uint8) * 255
    if not m.any():
        return page_bgr
    k = max(9, int(0.03 * min(m.shape)) | 1)
    ring = cv.subtract(cv.dilate(m, np.ones((k, k), np.uint8)), m) > 0
    g = cv.cvtColor(page_bgr, cv.COLOR_BGR2GRAY)
    if not ring.any():
        return page_bgr
    sel = ring & (g >= np.percentile(g[ring], 40))   # paper pixels only, not ink
    col = np.median(page_bgr[sel], axis=0) if sel.any() else np.array([255, 255, 255])
    a = cv.GaussianBlur(m, (0, 0), max(2.0, 0.004 * min(m.shape))).astype(np.float32)[..., None] / 255.0
    a = np.maximum(a, (m > 0)[..., None].astype(np.float32))   # inside: fully filled
    fill = np.empty_like(page_bgr); fill[:] = col.astype(np.uint8)
    return (page_bgr.astype(np.float32) * (1 - a) + fill.astype(np.float32) * a).astype(np.uint8)


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


def estimate_noise(bgr: np.ndarray) -> float:
    """Rough sensor-noise sigma (median absolute deviation of the Laplacian on gray)."""
    g = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY).astype(np.float32)
    lap = cv.Laplacian(g, cv.CV_32F)
    return float(np.median(np.abs(lap - np.median(lap))) / 0.6745 / 2.0)


def _denoise(bgr: np.ndarray, min_h: float = 3.0, max_h: float = 6.0) -> np.ndarray:
    """Remove sensor noise BEFORE any contrast step (otherwise it gets amplified).

    FAST version (round 6). The old version ran colour non-local means (template 7,
    search 21) and took 4-12 s on a Kirin 710. This one is ~6x faster with the same look:
      * brightness (Y) only: non-local means with template 5, search 11
      * colour (Cr, Cb): colour noise is blotchy and low-frequency, so a blur at 1/4 size
        is enough and costs almost nothing
      * clean, well-lit photos (low measured noise) skip the step entirely
    Strength still adapts to the measured noise so fine print is not smeared."""
    h, w = bgr.shape[:2]
    sigma = estimate_noise(bgr)
    if sigma < 1.5:                       # good light: nothing worth removing
        return bgr
    strength = float(np.clip(sigma * 0.8, min_h, max_h))
    ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb)
    y, cr, cb = cv.split(ycc)
    y = cv.fastNlMeansDenoising(y, None, strength, 5, 11)
    sm = (max(1, w // 4), max(1, h // 4))

    def chroma(c):
        c = cv.resize(c, sm, interpolation=cv.INTER_AREA)
        c = cv.GaussianBlur(c, (0, 0), 1.2)
        return cv.resize(c, (w, h), interpolation=cv.INTER_LINEAR)

    return cv.cvtColor(cv.merge([y, chroma(cr), chroma(cb)]), cv.COLOR_YCrCb2BGR)


def denoise_preview(bgr: np.ndarray) -> np.ndarray:
    """Instant, display-only clean-up for the first preview (~10x cheaper than _denoise).
    Replaced by the real result as soon as the background job finishes."""
    sigma = estimate_noise(bgr)
    if sigma < 1.5:
        return bgr
    return cv.bilateralFilter(bgr, 5, float(np.clip(sigma * 6, 15, 40)), 3)


def blurry_regions(warped_bgr: np.ndarray, grid: int = 3, ratio: float = 0.4, min_cells: int = 2):
    """Find parts of a page that are much blurrier than its sharpest part (camera shake or
    focus fall-off). Returns (row, col) cells of a grid x grid split, or [] when the page is
    evenly sharp or has too little detail to judge. Run on the cropped page before filters.

    Measure: on the strongest edges of each cell, |Laplacian| / |gradient|. For an edge
    blurred by sigma this is ~1/sigma, and it does not depend on how dark the text is."""
    g = cv.cvtColor(warped_bgr, cv.COLOR_BGR2GRAY).astype(np.float32)
    s = 1200.0 / max(g.shape[:2])
    if s < 1:
        g = cv.resize(g, None, fx=s, fy=s, interpolation=cv.INTER_AREA)
    g = cv.GaussianBlur(g, (0, 0), 0.8)                # ignore pixel noise
    gx, gy = cv.Sobel(g, cv.CV_32F, 1, 0), cv.Sobel(g, cv.CV_32F, 0, 1)
    grad = cv.magnitude(gx, gy)
    lap = np.abs(cv.Laplacian(g, cv.CV_32F, ksize=3))
    H, W = g.shape
    my, mx = int(H * 0.05), int(W * 0.05)              # skip page borders / shadows
    scores = {}
    for r in range(grid):
        for c in range(grid):
            y0, y1 = max(my, r * H // grid), min(H - my, (r + 1) * H // grid)
            x0, x1 = max(mx, c * W // grid), min(W - mx, (c + 1) * W // grid)
            gr, lp = grad[y0:y1, x0:x1], lap[y0:y1, x0:x1]
            strong = gr > max(60.0, float(np.percentile(gr, 97)))
            if strong.sum() > 150:                     # enough edges to judge
                scores[(r, c)] = float(np.median(lp[strong] / gr[strong]))
    if len(scores) < 3:
        return []
    best = max(scores.values())
    bad = sorted(k for k, v in scores.items() if v < ratio * best)
    # Round 7: users got far too many warnings. Only warn when a clear part of the page
    # (2+ cells of 9) is much softer than the sharpest part. A missed mild blur is better
    # than nagging on every page.
    return bad if len(bad) >= min_cells else []


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


DET_DEBUG = False
BG_SIZE, BG_KERNEL, BG_SIGMA = 500.0, 7, 2.5
BG_DEBUG = False


def _paper_background(f: np.ndarray) -> np.ndarray:
    """Paper brightness per channel (float, full size), following shadows closely.

    Works at 500 px: a small dilate + median removes text, so the estimate follows the
    soft edge of a phone/hand shadow instead of smearing it (the old 400 px / median 21
    version left a grey blob where the phone's shadow was). Large dark areas that are not
    shadow (photos, black boxes, the dark rim of a page) are filled from the surrounding
    paper, so a photo on the page keeps its darkness instead of being washed out."""
    h, w = f.shape[:2]
    s = BG_SIZE / max(h, w)
    sw, sh = max(1, int(w * s)), max(1, int(h * s))
    small = cv.resize(np.clip(f, 0, 255).astype(np.uint8), (sw, sh), interpolation=cv.INTER_AREA)
    kk = BG_KERNEL
    k = cv.getStructuringElement(cv.MORPH_RECT, (kk, kk))
    # CLOSE (dilate then erode), not just dilate: removes dark text but keeps the edge
    # of a shadow where it is. A plain dilate moved shadow edges by half a kernel, which
    # left a dark streak along every hard shadow (round 9).
    bg = cv.medianBlur(cv.morphologyEx(small, cv.MORPH_CLOSE, k), kk + 2)
    Y = cv.cvtColor(bg, cv.COLOR_BGR2GRAY).astype(np.float32)
    P = float(np.percentile(Y, 90))
    # Which dark areas are SHADOWS (divide them out) and which are OBJECTS such as a
    # photo, a black headphone, a dark box (protect them: fill the background there from
    # the paper around)? Per dark area (round 11, tested on real tube-light photos):
    #   * shadow if it is nearly uniform inside (cvar < 0.10), or
    #   * shadow if its outline is SOFT: a shadow fades out over a penumbra, an object has
    #     a crisp outline. Measured on the text-free background: 90th percentile of the
    #     gradient along the area's outline divided by the area's contrast to the paper.
    #     Shadows (hand, phone, lamp; even hard ones) measured 0.02-0.19, objects on
    #     packaging 0.22-0.52. Threshold 0.20.
    # Ink-based rules (rounds 9-10) misjudged real photos: thin handwriting under a soft
    # shadow was missed, and the edges of objects were counted as ink.
    gm = cv.magnitude(cv.Sobel(Y, cv.CV_32F, 1, 0), cv.Sobel(Y, cv.CV_32F, 0, 1)) / 8.0
    dark = (Y < 0.85 * P).astype(np.uint8)
    n, lab, st, _ = cv.connectedComponentsWithStats(dark, connectivity=8)
    hole = np.zeros_like(dark)
    min_area = 0.004 * dark.size
    k5 = np.ones((5, 5), np.uint8)
    for i in range(1, n):
        if st[i, cv.CC_STAT_AREA] < min_area:
            continue
        m = lab == i
        mu8 = m.astype(np.uint8)
        inner = cv.erode(mu8, k).astype(bool)
        if inner.sum() < 20:
            inner = m
        vals = Y[inner]
        cvar = float(vals.std() / max(1.0, vals.mean()))
        band = (cv.dilate(mu8, k5) - cv.erode(mu8, k5)).astype(bool)
        contrast = max(1.0, P - float(np.median(Y[m])))
        edge_sharp = float(np.percentile(gm[band], 90)) / contrast if band.any() else 0.0
        is_shadow = cvar < 0.10 or edge_sharp < 0.20
        if BG_DEBUG:
            print(f"    dark area {st[i, cv.CC_STAT_AREA] / dark.size:.1%}: cvar={cvar:.3f} edge={edge_sharp:.3f} -> {'shadow' if is_shadow else 'object'}")
        if not is_shadow:
            hole[m] = 255                                   # protect the whole object
    hole = cv.morphologyEx(hole, cv.MORPH_OPEN, k)          # drop thin shadow-edge bands
    hole = cv.dilate(hole, k)
    if 0 < cv.countNonZero(hole) < 0.6 * hole.size:
        bg = cv.inpaint(bg, hole, 15, cv.INPAINT_TELEA)
    bg = cv.GaussianBlur(bg.astype(np.float32), (0, 0), BG_SIGMA)   # float + blur -> no steps
    return cv.resize(bg, (w, h), interpolation=cv.INTER_CUBIC)


def _text_page_strength(gray: np.ndarray) -> float:
    """1.0 for a text page (paper + dark ink, few mid-tones), 0.0 for a photo-heavy page
    (packaging, photos). Fades between, never a hard switch."""
    g = cv.resize(gray, (max(1, gray.shape[1] // 4), max(1, gray.shape[0] // 4)), interpolation=cv.INTER_AREA)
    p = float(np.percentile(g, 85))
    mid = float(((g > 0.35 * p) & (g < 0.80 * p)).mean())
    return float(np.clip((0.22 - mid) / 0.10, 0.0, 1.0))


def flatten_page(bgr: np.ndarray, denoised: bool = False) -> np.ndarray:
    """Shared first step of Auto, Color boost, Grayscale and B&W print (round 9):
    denoise -> white balance -> shadow removal. Returns FLOAT32 BGR (0..255+), not rounded.
    Pass denoised=True when `bgr` is already the cached cleaned base (round 6)."""
    img = bgr if denoised else _denoise(bgr)
    f = img.astype(np.float32)
    # gray-world white balance (strength 0.6)
    mean = f.reshape(-1, 3).mean(0)
    f *= 1.0 + 0.6 * (mean.mean() / np.maximum(mean, 1.0) - 1.0)
    # Shadow removal: divide by the paper background. Text pages get the full effect
    # (shadows gone, like CamScanner); photo-heavy pages keep 25% of the original light.
    bg = _paper_background(f)
    flat = f / np.maximum(bg, 30.0) * 245.0
    # Decide "text page or photo-heavy page" on the shadow-free image. (Round 9: deciding
    # on the original let shadows count as mid-tones, so shadowed text pages were treated
    # as photos and kept 25% of the shadow.)
    doc = _text_page_strength(cv.cvtColor(np.clip(flat, 0, 255).astype(np.uint8), cv.COLOR_BGR2GRAY))
    blend = 0.75 + 0.25 * doc
    return blend * flat + (1.0 - blend) * f


def filter_auto_color(bgr: np.ndarray, chroma: float = 1.10, denoised: bool = False) -> np.ndarray:
    """Default 'Auto': clean, bright page, colours kept. For paper documents.
    IMPORTANT: every step after the denoise works in float and the image is rounded to
    8-bit only once, at the end. Rounding between steps and then stretching contrast is
    what makes the grey 'marble' / contour lines on plain paper."""
    f = flatten_page(bgr, denoised)
    # to float Lab (L 0..100)
    lab = cv.cvtColor(np.clip(f / 255.0, 0, 1), cv.COLOR_BGR2LAB)
    L = lab[:, :, 0]
    lo, hi = np.percentile(L, (1, 99.5))
    L = np.clip((L - lo) / max(1e-3, hi - lo) * 99.0, 0, 100)        # global levels
    L, chroma_k, wstrength = _whiten_paper(L, lab[:, :, 1], lab[:, :, 2])
    L = _despeckle_L(L, wstrength,                                    # round 11b: dim-light grain
                     np.sqrt(lab[:, :, 1] ** 2 + lab[:, :, 2] ** 2))
    lab[:, :, 0] = L
    lab[:, :, 1] *= chroma_k * chroma                                 # neutral paper, +10% colour elsewhere
    lab[:, :, 2] *= chroma_k * chroma
    out = cv.cvtColor(lab, cv.COLOR_LAB2BGR) * 255.0
    out = np.clip(out + 0.35 * (out - cv.GaussianBlur(out, (0, 0), 1.2)), 0, 255)   # unsharp
    return (out + 0.5).astype(np.uint8)                               # the ONLY rounding


def clean_page_border(bgr: np.ndarray, band: float = 0.05) -> np.ndarray:
    """Remove the dark slivers of table/background left along the page edges.

    Happens when the crop sits slightly outside the paper, and always with curled or wavy
    page edges (no 4-corner crop can follow a curve). Printed, these slivers show as black
    lines around the page. CamScanner hides them; so do we.

    Dark areas that touch the image edge and stay within `band` (5%) of it are painted with
    the paper colour. Dark areas that reach deeper than the band (a black header bar, a
    photo printed to the edge) are page content and are left alone.
    Run on the FILTERED page, Document mode only (not ID Card / Passport)."""
    h, w = bgr.shape[:2]
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY)
    P = float(np.percentile(gray, 90))                 # paper brightness
    dark = (gray < 0.80 * P).astype(np.uint8)
    b = max(2, int(round(band * min(h, w))))
    b2 = 2 * b
    # distance of every pixel from the nearest image edge
    yy, xx = np.mgrid[0:h, 0:w]
    depth = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    zone = (depth < b2).astype(np.uint8)
    n, lab, st, _ = cv.connectedComponentsWithStats(dark & zone, connectivity=8)
    if n <= 1:
        return bgr
    # max depth per component, and whether it touches the image edge
    maxd = np.zeros(n, np.int32)
    np.maximum.at(maxd, lab.ravel(), depth.ravel() * (lab.ravel() > 0))
    touch = np.zeros(n, bool)
    edge = np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])
    touch[np.unique(edge)] = True
    remove = touch & (maxd < b)
    remove[0] = False
    mask = remove[lab].astype(np.uint8) * 255
    if not mask.any():
        return bgr
    mask = cv.dilate(mask, cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5)))   # include the soft rim
    paper = bgr[gray >= 0.92 * P]
    colour = np.median(paper, axis=0) if len(paper) else np.array([255, 255, 255])
    out = bgr.copy()
    out[mask > 0] = colour.astype(np.uint8)
    return out


WHITEN_DEBUG = False


def _whiten_paper(L: np.ndarray, a: np.ndarray, b: np.ndarray):
    """Float Lab in, (new L, chroma multiplier, strength 0..1) out. If the page is mostly plain paper,
    push the paper to pure white with a soft ramp so no edge or step is visible. Text
    and coloured areas are kept. Small brightness waves left on paper otherwise show
    as grey 'marble' patches."""
    chroma = np.sqrt(a * a + b * b)
    paperish = (chroma < 12) & (L > np.percentile(L, 40))
    pL = float(np.percentile(L[paperish], 15))   # nearly all paper is brighter than this
    # Gate: a text page is paper + dark ink with few mid-tones. Photos, packaging and
    # pale printed letters have many mid-tones -> fade the effect out, never a hard switch.
    mid = float(((L > 0.35 * pL) & (L < 0.80 * pL)).mean())
    strength = float(np.clip((0.10 - mid) / 0.03, 0.0, 1.0))   # mid<=0.07 full, >=0.10 off
    if WHITEN_DEBUG:
        print(f"    whiten: mid={mid:.3f} strength={strength:.2f}")
    if strength == 0.0:
        return L, np.ones_like(L), 0.0
    t0 = 0.70 * pL
    # Smoothstep from t0 (unchanged) to pL (white). Below t0: unchanged, so text keeps its
    # weight. The curve and its slope are continuous -> no contour lines.
    x = np.clip((L - t0) / max(1e-3, pL - t0), 0, 1)
    s = x * x * (3 - 2 * x)
    s *= strength
    L2 = L + s * (100.0 - L)
    k = 1.0 - 0.8 * s * (chroma < 20)          # fade paper tint to neutral
    return L2, k, strength


SPECK_MAX_AREA = 2.5e-5    # of the page (about 30 px on a 1300 x 2000 page)
SPECK_MIN_L = 40.0         # a speck is light grey: none of its pixels darker than this (Lab L 0..100)


def _despeckle_L(L: np.ndarray, strength: float, chroma: np.ndarray | None = None) -> np.ndarray:
    """Round 11b. Dim-light photos leave small grey sensor-noise dots on the paper after
    whitening (they are darker than the whitening ramp start and then get sharpened).
    Remove tiny, LIGHT-grey, isolated dots: text, i-dots, commas and pen strokes are darker
    (min L < 40) or bigger and are never touched. Float L (0..100) in and out.
    Only on text pages (strength = the whitening strength, 0..1), and only on NEUTRAL grey
    pixels (chroma < 12): highlighter, stamps and coloured print are never touched."""
    if strength <= 0.0:
        return L
    h, w = L.shape
    # 1) faint grain: light grey (L > 75) and not next to ink (no pixel darker than 60
    #    within ~0.25% of the page) -> paper. Anti-aliased text edges are next to ink: kept.
    ink = (L < 60.0).astype(np.uint8)
    r = max(2, int(0.0025 * max(h, w)))
    near_ink = cv.dilate(ink, cv.getStructuringElement(cv.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))) > 0
    neutral = np.ones_like(L, bool) if chroma is None else (chroma < 12.0)
    grain = (L > 75.0) & (L < 100.0) & ~near_ink & neutral
    L = L.copy()
    L[grain] = L[grain] + strength * (100.0 - L[grain])
    # 2) darker specks: tiny isolated dots that are still light-ish (min L > 40)
    notwhite = (L < 92.0).astype(np.uint8)
    n, lbl, st, _ = cv.connectedComponentsWithStats(notwhite, connectivity=8)
    if n <= 1:
        return L
    amax = max(4, int(SPECK_MAX_AREA * h * w))
    small = st[:, cv.CC_STAT_AREA] <= amax
    small[0] = False
    # darkest pixel of each component (one pass: min L per label)
    mins = np.full(n, 100.0, np.float32)
    np.minimum.at(mins, lbl.ravel(), L.ravel().astype(np.float32))
    speck = small & (mins > SPECK_MIN_L)
    if not speck.any():
        return L
    m = speck[lbl] & neutral
    L[m] = L[m] + strength * (100.0 - L[m])
    return L


def _levels_L(bgr: np.ndarray, lo_pct: float, hi_pct: float) -> np.ndarray:
    lab = cv.cvtColor(bgr, cv.COLOR_BGR2LAB)
    L = lab[:, :, 0].astype(np.float32)
    lo, hi = np.percentile(L, lo_pct), np.percentile(L, hi_pct)
    lab[:, :, 0] = np.clip((L - lo) / max(1.0, hi - lo) * 252.0, 0, 255).astype(np.uint8)
    return cv.cvtColor(lab, cv.COLOR_LAB2BGR)


def filter_id_color(bgr: np.ndarray) -> np.ndarray:
    """'ID colour' (default in ID/Passport modes): no background whitening —
    a card is not white paper. Clean, sharp, true colours for colour copies.
    Denoise is capped lower than for documents: cards have fine guilloche print and
    small text that strong denoising smears."""
    img = _denoise(bgr, min_h=2.0, max_h=3.0)
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


def filter_color_boost(bgr: np.ndarray, denoised: bool = False) -> np.ndarray:
    """'Color boost': Auto with stronger colours (stamps, highlighter, coloured forms)."""
    return filter_auto_color(bgr, chroma=1.35, denoised=denoised)


def filter_grayscale(bgr: np.ndarray, denoised: bool = False) -> np.ndarray:
    """'Grayscale': Auto without colour (same clean white paper, no shadows)."""
    g = cv.cvtColor(filter_auto_color(bgr, chroma=0.0, denoised=denoised), cv.COLOR_BGR2GRAY)
    return cv.cvtColor(g, cv.COLOR_GRAY2BGR)


def filter_bw_print(bgr: np.ndarray, denoised: bool = False) -> np.ndarray:
    """'B&W print': pure black text on white, for photocopies.
    Round 9: starts from flatten_page() (shadows already removed) instead of its own
    background estimate, so shadow edges no longer turn into black streaks."""
    # Threshold the finished Grayscale page: paper is already pure white and faint shadow
    # rims are already gone, so only real ink is dark. A pixel is ink if it is clearly
    # darker than its neighbourhood (adaptive, C=18) AND darker than 200 overall.
    gray = cv.cvtColor(filter_grayscale(bgr, denoised), cv.COLOR_BGR2GRAY)
    block = max(15, (min(gray.shape[:2]) // 40) | 1)
    loc = cv.adaptiveThreshold(gray, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, block, 18)
    bw = np.where((loc == 0) & (gray < 200), 0, 255).astype(np.uint8)
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
# 5. Passport photo: natural face brightening (round 11b)
#     After the background swap. person = selfie-segmentation mask (float 0..1),
#     face_box = ML Kit face detection box (x0, y0, x1, y1). Background untouched.
#     No beauty filter, no skin smoothing: official photos must look natural.
# ---------------------------------------------------------------------------
FACE_TARGET_L = 64.0       # Lab L (0..100) of the middle of the face


def passport_brighten(bgr: np.ndarray, person: np.ndarray, face_box) -> np.ndarray:
    x0, y0, x1, y1 = [int(v) for v in face_box]
    lab = cv.cvtColor(bgr.astype(np.float32) / 255.0, cv.COLOR_BGR2LAB)
    L, a, b = cv.split(lab)
    body = person > 0.5
    if body.sum() < 100:
        return bgr
    lo = float(np.percentile(L[body], 1))
    hi = float(np.percentile(L[body], 99.5))
    hi2 = hi + 0.35 * (100.0 - hi)                    # highlights: lift a little, never clip
    Ln = np.clip((L - lo) / max(1e-3, hi - lo) * (hi2 - 3.0) + 3.0, 0, 100)
    fm = float(np.median(Ln[y0:y1, x0:x1]))
    if fm < 1.0:
        return bgr
    g = float(np.clip(np.log(FACE_TARGET_L / 100.0) / np.log(fm / 100.0), 0.75, 1.0))
    Ln = 100.0 * np.power(Ln / 100.0, g)              # midtones up, black and white points kept
    Lo = person * Ln + (1.0 - person) * L
    k = 1.0 + 0.22 * person                           # brightening greys skin: colour back +22%
    out = cv.cvtColor(np.dstack([Lo, a * k, b * k]).astype(np.float32), cv.COLOR_LAB2BGR) * 255.0
    out = out + 0.4 * (out - cv.GaussianBlur(out, (0, 0), 1.5)) * person[..., None]   # eyes, hair
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


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
        w = warp_curved(img, q, mode) if found else warp(img, q, mode)   # round 11b: bent pages
        fingers = find_fingers(w) if mode == "document" else None
        crop_vis = w.copy()
        if fingers is not None:
            cv.drawContours(crop_vis, finger_outline(fingers), -1, (51, 194, 255), max(2, w.shape[1] // 300))
        tiles = [_label(_fit(vis, 420), f"{name}: {'found' if found else 'NOT found'} ({src})"),
                 _label(_fit(crop_vis, 420), "Crop" + (" + fingers found" if fingers is not None else ""))]
        if mode == "id":
            tiles.append(_label(_fit(filter_id_color(w), 420), "ID colour"))
        else:
            auto = clean_page_border(filter_auto_color(w))
            tiles.append(_label(_fit(auto, 420), "Auto (colour)"))
            if fingers is not None:
                tiles.append(_label(_fit(remove_fingers(auto, fingers), 420), "Auto + Remove fingers"))
        tiles.append(_label(_fit(filter_bw_print(w) if mode == "id" else clean_page_border(filter_bw_print(w)), 420), "B&W print"))
        row = np.hstack([np.pad(t, ((6, 6), (6, 6), (0, 0)), constant_values=255) for t in tiles])
        rows.append(row)
        print(f"{name:16s} mode={mode:9s} found={found} score={score:.3f} via={src} sharpness={sharpness(img):.0f} "
              f"crop={w.shape[1]}x{w.shape[0]} fingers={'yes' if fingers is not None else 'no'}")
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
