# camerawesome 2.5.0, patched for Flash Dox (round 11c)

Copied from pub.dev `camerawesome` 2.5.0 (MIT, see LICENSE) without its docs,
example and tests. One change, Android only:

- `CameraXState.kt`: `ImageCapture` uses the size set with
  `CamerawesomePlugin.setPhotoSize` (`photoResolutionSelector()`: the closest
  size at or below it, else above, in the current aspect ratio). In 2.5.0 that
  line was commented out, so photos were always the sensor's largest size.
  Flash Dox takes ~8 MP photos and the full sensor only in HD.

To update: copy the new version the same way and re-apply the change (search
for "Flash Dox patch").
