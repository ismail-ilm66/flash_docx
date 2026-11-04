# iOS share-in (X-2): one-time Xcode setup

The code is here; the target has to be created in Xcode (the project file
can't safely be edited by hand). About 10 minutes:

1. Open `ios/Runner.xcworkspace`. **File → New → Target → Share Extension.**
   Product name `ShareExtension`, language Swift, bundle id
   `com.flashdox.app.ShareExtension`. Don't activate the scheme when asked.
2. Delete the generated `ShareViewController.swift`, `MainInterface.storyboard`
   and `Info.plist` in the new group, then **add the three files from this
   folder** (`ShareViewController.swift`, `Info.plist`,
   `ShareExtension.entitlements`) to the `ShareExtension` target.
   In the target's Build Settings set *Info.plist File* to
   `ShareExtension/Info.plist` and *Code Signing Entitlements* to
   `ShareExtension/ShareExtension.entitlements`.
3. **Signing & Capabilities** on *both* `Runner` and `ShareExtension`: add
   **App Groups** and tick `group.com.flashdox.app`. For `Runner`, point
   *Code Signing Entitlements* at `Runner/Runner.entitlements` (already written).
4. Set the extension's deployment target to the same iOS version as Runner (15.5).
5. In `Podfile`, add the extension target so it builds with the workspace:

   ```ruby
   target 'ShareExtension' do
     use_frameworks!
   end
   ```

   then `cd ios && pod install`.
6. Build and run `Runner` on a device. In Photos, share a picture → Flash Dox
   appears in the sheet; the app opens on Adjust edges with the image through
   the same pipeline as camera and import.

Already wired without Xcode: the URL scheme `flashdox://` in `Runner/Info.plist`,
the receiver in `Runner/AppDelegate.swift` (same channel names as Android, so
`ShareInService` in Dart needs no change), and the entitlement files.

Scope note: the extension accepts images only. The plan says the app never
opens PDFs, so sharing a PDF into it is not supported on either platform.
