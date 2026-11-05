"""Dumps the owner's reference pipeline outputs for the Dart parity tests.

For each photo in test/fixtures/edges/*.jpg:
  * <name>.json            detected corners (normalised TL,TR,BR,BL), score, map
  * reference/<name>_warp.png        reference warp (lossless), the shared input
  * reference/<name>_auto.png        filter_auto_color(warp)
  * reference/<name>_id.png          filter_id_color(warp)
  * reference/<name>_bw.png          filter_bw_print(warp)
  * reference/<name>_ocr.png         ocr_image(warp)
  * reference/<name>_overlay.jpg     photo with the detected quad, for review
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
    json.dump(meta, open(os.path.join(edges, name + '.json'), 'w'), indent=1)
    warped = ref.warp(img, q, mode)
    cv.imwrite(os.path.join(out, f'{name}_warp.png'), warped)
    cv.imwrite(os.path.join(out, f'{name}_auto.png'), ref.filter_auto_color(warped))
    cv.imwrite(os.path.join(out, f'{name}_id.png'), ref.filter_id_color(warped))
    cv.imwrite(os.path.join(out, f'{name}_bw.png'), ref.filter_bw_print(warped))
    cv.imwrite(os.path.join(out, f'{name}_ocr.png'), ref.ocr_image(warped))
    vis = img.copy()
    cv.polylines(vis, [q.astype(np.int32)], True, (0, 220, 0), 4)
    cv.imwrite(os.path.join(out, f'{name}_overlay.jpg'), vis)
    print(f'{name}: {w}x{h} found via {src} score={score:.3f} sharpness={ref.sharpness(img):.0f} corners={meta["tl"]},{meta["tr"]},{meta["br"]},{meta["bl"]}')
