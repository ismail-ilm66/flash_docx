// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Flash Dox';

  @override
  String get navHome => 'Home';

  @override
  String get navSettings => 'Settings';

  @override
  String get navScan => 'Scan';

  @override
  String get homeTitle => 'Flash Dox';

  @override
  String get homeQuickActions => 'Quick actions';

  @override
  String get homeRecentActivity => 'Recent activity';

  @override
  String get homeSearchHint => 'Search documents';

  @override
  String get homeEmptyTitle => 'No scans yet';

  @override
  String get homeEmptyBody =>
      'Tap the camera button to scan your first document, or import photos from your gallery.';

  @override
  String get homeImport => 'Import';

  @override
  String get homeImportGallery => 'From gallery';

  @override
  String get homeImportFiles => 'From files';

  @override
  String get modeSingle => 'Single';

  @override
  String get modeBatch => 'Batch';

  @override
  String get modeIdCard => 'ID card';

  @override
  String get modePassport => 'Passport';

  @override
  String get activityCreated => 'Scanned';

  @override
  String get activityEdited => 'Edited';

  @override
  String get activitySharedPdf => 'Shared as PDF';

  @override
  String get activitySharedImages => 'Shared as images';

  @override
  String get activitySavedToPhone => 'Saved to phone';

  @override
  String get activityTextCopied => 'Text copied';

  @override
  String get activityPrintLayout => 'Print layout created';

  @override
  String pagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get cameraTitle => 'Scan';

  @override
  String get cameraFlashOn => 'Flash on';

  @override
  String get cameraFlashOff => 'Flash off';

  @override
  String get cameraGuideFront => 'Front side';

  @override
  String get cameraGuideBack => 'Back side';

  @override
  String get cameraGuidePassport => 'Passport data page';

  @override
  String get cameraGuideSingle => 'Fit the document in the frame';

  @override
  String cameraGuideBatch(int n) {
    return 'Page $n';
  }

  @override
  String get cameraDone => 'Done';

  @override
  String get cameraPermissionTitle => 'Camera access needed';

  @override
  String get cameraPermissionBody =>
      'Flash Dox needs the camera to scan documents. You can allow it in Settings.';

  @override
  String get cameraOpenSettings => 'Open settings';

  @override
  String get cameraImportInstead => 'Import instead';

  @override
  String get adjustTitle => 'Adjust edges';

  @override
  String get adjustHint => 'Drag the corners to fit the document';

  @override
  String get adjustAuto => 'Auto';

  @override
  String get adjustRotateLeft => 'Rotate left';

  @override
  String get adjustRotateRight => 'Rotate right';

  @override
  String get adjustRetake => 'Retake';

  @override
  String get adjustDeletePage => 'Delete page';

  @override
  String get adjustNext => 'Next';

  @override
  String get enhanceTitle => 'Enhance';

  @override
  String get enhanceBrightness => 'Brightness';

  @override
  String get enhanceContrast => 'Contrast';

  @override
  String get enhanceApplyAll => 'Apply to all pages';

  @override
  String get enhanceAppliedAll => 'Applied to all pages';

  @override
  String get enhanceHoldToCompare => 'Hold to compare';

  @override
  String get enhanceDone => 'Done';

  @override
  String get enhanceReset => 'Reset';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterAuto => 'Auto';

  @override
  String get filterColorBoost => 'Color boost';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBwPrint => 'B&W print';

  @override
  String get viewerEdit => 'Edit';

  @override
  String get viewerText => 'Text';

  @override
  String get viewerPrint => 'Print';

  @override
  String get viewerShare => 'Share';

  @override
  String get viewerAddPages => 'Add pages';

  @override
  String get viewerRename => 'Rename';

  @override
  String get viewerReorder => 'Reorder pages';

  @override
  String get viewerDelete => 'Delete document';

  @override
  String get viewerDeletePage => 'Delete page';

  @override
  String viewerPageOf(int n, int total) {
    return '$n of $total';
  }

  @override
  String get viewerUntitled => 'Untitled';

  @override
  String get renameTitle => 'Rename document';

  @override
  String get renameHint => 'Document name';

  @override
  String get deleteDocTitle => 'Delete this document?';

  @override
  String get deleteDocBody =>
      'All pages will be removed from your phone. This can\'t be undone.';

  @override
  String get deletePageTitle => 'Delete this page?';

  @override
  String get deletePageBody => 'The page will be removed from the document.';

  @override
  String get ocrTitle => 'Extracted text';

  @override
  String get ocrThisPage => 'This page';

  @override
  String get ocrAllPages => 'All pages';

  @override
  String get ocrCut => 'Cut';

  @override
  String get ocrCopyAll => 'Copy all';

  @override
  String get ocrShareTxt => 'Share .txt';

  @override
  String get ocrCopied => 'Text copied';

  @override
  String get ocrEmpty => 'No text found on this page';

  @override
  String get ocrWorking => 'Reading text…';

  @override
  String ocrPageSeparator(int n) {
    return '--- Page $n ---';
  }

  @override
  String get shareTitle => 'Share';

  @override
  String get shareFormat => 'Format';

  @override
  String get sharePdf => 'PDF';

  @override
  String get shareJpg => 'JPG';

  @override
  String get sharePng => 'PNG';

  @override
  String get shareQuality => 'Quality';

  @override
  String get shareQualityStandard => 'Standard';

  @override
  String get shareQualityHigh => 'High quality';

  @override
  String get sharePageSize => 'Page size';

  @override
  String get sharePageA4 => 'A4';

  @override
  String get sharePageLetter => 'Letter';

  @override
  String get sharePageFit => 'Fit to image';

  @override
  String get shareFileName => 'File name';

  @override
  String get shareButton => 'Share';

  @override
  String get shareSaveToPhone => 'Save to phone';

  @override
  String get shareSaved => 'Saved to phone';

  @override
  String get sharePreparing => 'Preparing…';

  @override
  String get shareWatchVideo => 'Video';

  @override
  String get printTitle => 'Print layout';

  @override
  String get printOutput => 'Output';

  @override
  String get printOutputImage => 'Image';

  @override
  String get printOutputDoubleSided => 'Double-sided PDF';

  @override
  String get printOutputOnePage => 'One-page PDF';

  @override
  String get printCopies => 'Copies per sheet';

  @override
  String get printActualSize =>
      'Print at 100% / Actual size, flip on long edge.';

  @override
  String get printShare => 'Share';

  @override
  String get printSave => 'Save';

  @override
  String get printNotAvailable => 'Not available for this document';

  @override
  String get unlockTitle => 'Unlock with a short video';

  @override
  String unlockBody(String feature) {
    return 'Watch one video to unlock $feature for this export.';
  }

  @override
  String get unlockWatch => 'Watch video';

  @override
  String get unlockNotNow => 'Not now';

  @override
  String get unlockOffline =>
      'Needs internet for the video. Free options still work.';

  @override
  String get unlockLoading => 'Loading video…';

  @override
  String get featureHighQuality => 'High quality export';

  @override
  String get featurePng => 'PNG export';

  @override
  String get featureAllPagesText => 'Text from all pages';

  @override
  String get featureMoreCopies => 'More copies per sheet';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsScan => 'Scan';

  @override
  String get settingsDefaultFilter => 'Default filter';

  @override
  String get settingsDefaultMode => 'Default scan mode';

  @override
  String get settingsShare => 'Share';

  @override
  String get settingsDefaultFormat => 'Default format';

  @override
  String get settingsDefaultPageSize => 'Default page size';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsStorageUsed => 'Space used by scans';

  @override
  String get settingsClearTemp => 'Clear temporary files';

  @override
  String get settingsClearedTemp => 'Temporary files cleared';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsPrivacy => 'Privacy Policy';

  @override
  String get settingsFaq => 'FAQ';

  @override
  String get settingsRate => 'Rate Flash Dox';

  @override
  String get settingsShareApp => 'Share Flash Dox';

  @override
  String settingsVersion(String v) {
    return 'Version $v';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDone => 'Done';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonOk => 'OK';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSelectAll => 'Select all';

  @override
  String get commonCopy => 'Copy';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get errorStorage => 'Couldn\'t write to storage';

  @override
  String get errorImage => 'Couldn\'t process the image';

  @override
  String get errorOcr => 'Couldn\'t read text from the image';

  @override
  String get errorPdf => 'Couldn\'t build the PDF';

  @override
  String get errorPermission => 'Permission needed';

  @override
  String get errorOffline => 'No internet connection';
}
