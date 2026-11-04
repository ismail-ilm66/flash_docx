# Edge-detection fixtures

Drop real photos here, one JPEG per case, plus a sidecar JSON with the true
corners in normalised coordinates (0..1), ordered TL, TR, BR, BL:

```
receipt_wood_01.jpg
receipt_wood_01.json   → {"tl":[0.21,0.12],"tr":[0.80,0.10],"br":[0.83,0.91],"bl":[0.18,0.93]}
```

Optional keys: `"aspect": 1.585` (ID card) to run in ID mode, `"skip": true`.

`test/features/editor/edge_fixtures_test.dart` runs every pair and requires
each corner within 3% of the image width on at least 26 of 30 cases.
