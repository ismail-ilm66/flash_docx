# Flash Dox site

Static pages the app and the Play listing link to: `index.html` (home),
`privacy.html` (privacy policy) and `faq.html`. No build step; shared
styles in `style.css`, Manrope from `fonts/`, icon from the Android
launcher icon.

Published with GitHub Pages from the public repo
`ismail-ilm66/flash-dox-site` (root of `main`):

- Home: https://ismail-ilm66.github.io/flash-dox-site/
- Privacy policy: https://ismail-ilm66.github.io/flash-dox-site/privacy.html
- FAQ: https://ismail-ilm66.github.io/flash-dox-site/faq.html

`lib/core/constants/app_info.dart` (`siteUrl`) points the app's Settings
links here; the privacy URL also goes in Play Console.

To update: edit the files here, then copy this folder's contents to the
site repo and push. When the privacy policy changes, update "Last updated".
