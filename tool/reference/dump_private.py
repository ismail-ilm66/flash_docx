"""Reference outputs for the owner's private photos (round 11, P0-10).

Put the photos in test/fixtures/private/ (git-ignored: they are private
documents), then run:  python3 tool/reference/dump_private.py
For each <name>.jpg it writes, next to it:
  * <name>.json        detected corners (normalised TL, TR, BR, BL), source
  * <name>_warp.png    the reference crop (warp_curved in Document mode)
  * <name>_auto.png    filter_auto_color of that crop
test/features/editor/private_golden_test.dart compares the Dart port with
them (corners within 1 %, Auto within 3 levels on average).
"""
import glob, json, os, sys
import cv2 as cv

sys.path.insert(0, os.path.dirname(__file__))
import flashdox_reference as ref  # noqa: E402

folder = os.path.join(os.path.dirname(__file__), '..', '..', 'test', 'fixtures', 'private')
for p in sorted(glob.glob(os.path.join(folder, '*.jpg'))):
    name = os.path.splitext(os.path.basename(p))[0]
    mode = 'id' if name.startswith('id_') else 'document'
    img = cv.imread(p)
    h, w = img.shape[:2]
    q, score, src = ref.detect_document(img, mode)
    if q is None:
        print(f'{name}: NOT FOUND'); continue
    q = ref._order_corners(q)
    json.dump({'corners': [[float(x) / w, float(y) / h] for x, y in q], 'source': src, 'mode': mode},
              open(os.path.join(folder, f'{name}.json'), 'w'), indent=1)
    warped = ref.warp_curved(img, q, mode)
    cv.imwrite(os.path.join(folder, f'{name}_warp.png'), warped)
    cv.imwrite(os.path.join(folder, f'{name}_auto.png'), ref.filter_id_color(warped) if mode == 'id' else ref.filter_auto_color(warped))
    print(f'{name}: {src} score={score:.3f}')
