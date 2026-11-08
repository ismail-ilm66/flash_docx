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
  String get modeDocument => 'Document';

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
  String cameraGuideDocument(int n) {
    return 'Page $n · hold the phone flat over the page';
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
  String get adjustRotateLeft => 'Left';

  @override
  String get adjustRotateRight => 'Right';

  @override
  String get adjustRetake => 'Retake';

  @override
  String get adjustDeletePage => 'Delete';

  @override
  String get adjustNext => 'Next';

  @override
  String get enhanceTitle => 'Enhance';

  @override
  String get enhanceBrightness => 'Brightness';

  @override
  String get enhanceContrast => 'Contrast';

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
  String get filterIdColor => 'ID colour';

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
  String get shareQualityHigh => 'High';

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
  String get printOutputDoubleSided => 'PDF\ndouble-sided';

  @override
  String get printOutputOnePage => 'PDF\none page';

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
  String get featureHighQuality => 'High quality';

  @override
  String get featurePng => 'PNG export';

  @override
  String get featureAllPagesText => 'All pages';

  @override
  String get featureMoreCopies => 'More copies';

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
  String get settingsScan => 'Scanning';

  @override
  String get settingsDefaultFilter => 'Default filter';

  @override
  String get settingsShare => 'Sharing';

  @override
  String get settingsDefaultFormat => 'Default format';

  @override
  String get settingsDefaultPageSize => 'PDF page size';

  @override
  String get settingsStorage => 'Storage';

  @override
  String get settingsStorageUsed => 'Used by Flash Dox';

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
  String get settingsShareApp => 'Share the app';

  @override
  String settingsVersion(String v) {
    return 'Flash Dox · version $v';
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

  @override
  String get splashTagline => 'Scan. Clean. Share.';

  @override
  String get homeHeadline => 'What are we scanning today?';

  @override
  String get homeDocument => 'Docs';

  @override
  String get homeSortLatest => 'Latest';

  @override
  String get homeSortOldest => 'Oldest';

  @override
  String get homeSortName => 'Name';

  @override
  String get homeSortBy => 'Sort documents';

  @override
  String get homeNoResults => 'No documents match your search';

  @override
  String get commonMore => 'More options';

  @override
  String get cameraFlashOnShort => 'On';

  @override
  String get cameraFlashOffShort => 'Off';

  @override
  String get cameraTakePhoto => 'Take photo';

  @override
  String cameraReview(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review $count pages',
      one: 'Review 1 page',
    );
    return '$_temp0';
  }

  @override
  String get cameraRemoveLast => 'Remove last capture';

  @override
  String pageOfTotal(int n, int total) {
    return 'Page $n of $total';
  }

  @override
  String viewerCounter(int n, int total) {
    return '$n / $total';
  }

  @override
  String get viewerHoldToReorder => 'Hold to reorder';

  @override
  String dateTodayAt(String time) {
    return 'Today, $time';
  }

  @override
  String dateYesterdayAt(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get ocrHint =>
      'Read on your phone · works offline · you can edit before copying';

  @override
  String get ocrTxt => '.txt';

  @override
  String get ocrPrevPage => 'Previous page';

  @override
  String get ocrNextPage => 'Next page';

  @override
  String get shareOneFile => '1 file';

  @override
  String shareImagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get shareQualityStandardHint => 'Smaller file · for sharing';

  @override
  String get shareQualityHighHint => 'Best for printing';

  @override
  String shareButtonFormat(String format) {
    return 'Share $format';
  }

  @override
  String printSheetFronts(int n) {
    return 'Sheet $n · Fronts';
  }

  @override
  String printSheetBacks(int n) {
    return 'Sheet $n · Backs';
  }

  @override
  String printSheetCaption(String w, String h) {
    return 'A4 · cards at real size, $w × $h mm';
  }

  @override
  String printTipDuplex(String flip, String scale) {
    return 'Print double-sided, $flip, at $scale. Each back lands behind its front.';
  }

  @override
  String printTipSingle(String scale) {
    return 'Print at $scale so cards come out at their real size.';
  }

  @override
  String get printTipFlip => 'flip on long edge';

  @override
  String get printTipScale => '100% / Actual size';

  @override
  String get printShareImage => 'Share image';

  @override
  String unlockFeatureTitle(String feature) {
    return 'Unlock $feature';
  }

  @override
  String get unlockBodyHighQuality =>
      'Watch a short video to export this file at full resolution.';

  @override
  String get unlockBodyPng =>
      'Watch a short video to export lossless PNG images.';

  @override
  String get unlockBodyAllPagesText =>
      'Watch a short video to read the text of every page at once.';

  @override
  String get unlockBodyMoreCopies =>
      'Watch a short video to fit more copies on one sheet.';

  @override
  String get unlockFreeNote =>
      'Scanning, editing and standard sharing always stay free.';

  @override
  String get unlockNeedsInternet => 'Needs internet for the video';

  @override
  String get settingsChoose => 'Choose';

  @override
  String get addFromCamera => 'Camera';

  @override
  String get backLeaveTitle => 'Leave Flash Dox?';

  @override
  String get backLeave => 'Leave';

  @override
  String get backStay => 'Stay';

  @override
  String get discardScanTitle => 'Discard this scan?';

  @override
  String discardScanBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages will be lost.',
      one: '1 page will be lost.',
    );
    return '$_temp0';
  }

  @override
  String get discardScan => 'Discard';

  @override
  String get keepScanning => 'Keep scanning';

  @override
  String get adjustEdgesNotFound =>
      'Couldn\'t find the edges — drag the corners';

  @override
  String get settingsShutterSound => 'Shutter sound';

  @override
  String get settingsDefaultQuality => 'Default quality';

  @override
  String get printCutGuides => 'Cut guides';

  @override
  String get printSwapSides => 'Swap front/back';

  @override
  String printSheetOf(int n, int total) {
    return 'Sheet $n of $total';
  }

  @override
  String get shareLayout => 'Layout';

  @override
  String get shareLayoutOneImage => 'One image (front + back)';

  @override
  String get shareLayoutSeparate => 'Separate images';

  @override
  String get defaultDocName => 'Flash Scan';

  @override
  String get cameraBlurryTitle => 'Photo looks blurry';

  @override
  String get cameraRetake => 'Retake';

  @override
  String get cameraKeep => 'Keep';

  @override
  String get cameraDark => 'It\'s dark — turn on the flash for a sharper scan.';

  @override
  String get cameraUnreadable =>
      'That photo couldn\'t be read. Please take it again.';

  @override
  String get cameraStorageLow =>
      'Your phone storage is almost full — scans may be slow.';

  @override
  String get cameraStorageFull =>
      'Not enough storage to save scans. Free up space and try again.';

  @override
  String cameraPreparingProgress(int done, int total) {
    return 'Preparing $done of $total…';
  }

  @override
  String get settingsMagneticEdges => 'Magnetic edges';

  @override
  String get printQualityStandard => 'Standard · 300 DPI';

  @override
  String get printQualityHigh => 'High · 600 DPI';

  @override
  String get cameraHintDocument =>
      'Hold steady · edges are found automatically';

  @override
  String get cameraHintCard =>
      'Fit the card in the frame · move back if it\'s blurry';

  @override
  String get cameraCardBlurry => 'Card looks blurry';

  @override
  String get enhanceAdjust => 'Adjust';

  @override
  String enhanceAllPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get enhanceZoomIn => 'Zoom in';

  @override
  String get enhanceZoomOut => 'Zoom out';

  @override
  String sharePreparingPages(int done, int total) {
    return 'Preparing… $done/$total pages';
  }

  @override
  String get homeTools => 'Tools';

  @override
  String get toolPassportPhoto => 'Passport photo';

  @override
  String get toolSign => 'Sign document';

  @override
  String get toolShrinkPdf => 'Shrink PDF';

  @override
  String get toolExtractText => 'Extract text';

  @override
  String get pickDocumentTitle => 'Pick a document';

  @override
  String get pickDocumentEmpty => 'No documents yet. Scan one first.';

  @override
  String get shareMaxSize => 'Max file size';

  @override
  String get shareMaxSizeHint => 'For upload limits on forms and portals';

  @override
  String get maxSizeNoLimit => 'No limit';

  @override
  String maxSizeUnder(String size) {
    return 'Under $size';
  }

  @override
  String get maxSizeBody =>
      'The PDF is shrunk until it fits. Use this when a form or portal limits the upload size.';

  @override
  String get maxSizeNoteOriginal => 'Original size';

  @override
  String get maxSizeNote1mb => 'Email and most portals';

  @override
  String get maxSizeNote500kb => 'Common form limit';

  @override
  String get maxSizeNote200kb => 'Small text may get soft';

  @override
  String get maxSizeTagBest => 'Best';

  @override
  String get maxSizeTagSharp => 'Sharp';

  @override
  String get maxSizeTagGood => 'Good';

  @override
  String get maxSizeTagReadable => 'Readable';

  @override
  String get maxSizeCustom => 'Custom';

  @override
  String get maxSizeCustomHint => 'e.g. 300';

  @override
  String get maxSizeKb => 'KB';

  @override
  String shareReadySize(String size) {
    return 'Ready · $size';
  }

  @override
  String get shareHardToRead => 'Small text may be hard to read.';

  @override
  String get shareNeedsGrayscale =>
      'Can\'t fit in colour. Make it black and white to fit?';

  @override
  String get shareMakeGrayscale => 'Black and white';

  @override
  String shareCantFit(String size) {
    return 'Can\'t get under $size without making it unreadable. Try fewer pages or black and white.';
  }

  @override
  String get shareShrinking => 'Making it fit…';

  @override
  String get folderAll => 'All';

  @override
  String get folderBills => 'Bills';

  @override
  String get folderIds => 'IDs';

  @override
  String get folderEducation => 'Education';

  @override
  String get folderReceipts => 'Receipts';

  @override
  String get folderOther => 'Other';

  @override
  String folderEmpty(String folder) {
    return 'Nothing in $folder yet';
  }

  @override
  String smartLooksLike(String kind) {
    return 'Looks like $kind';
  }

  @override
  String smartRenameTo(String title, String folder) {
    return 'Rename to “$title” · $folder';
  }

  @override
  String get smartApply => 'Apply';

  @override
  String get smartDismiss => 'Dismiss suggestion';

  @override
  String get menuMoveToFolder => 'Move to folder';

  @override
  String movedToFolder(String folder) {
    return 'Moved to $folder';
  }

  @override
  String sidesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sides',
      one: '1 side',
    );
    return '$_temp0';
  }

  @override
  String get activitySigned => 'Signed';

  @override
  String get viewerSign => 'Sign';

  @override
  String get signTitle => 'Sign document';

  @override
  String get signHint => 'Drag to move · drag the corner to resize';

  @override
  String get signInk => 'Ink';

  @override
  String get signChange => 'Change signature';

  @override
  String get signAddDate => 'Add date';

  @override
  String get signAddSignature => 'Add signature';

  @override
  String get signRemove => 'Remove';

  @override
  String get signPrevPage => 'Previous page';

  @override
  String get signNextPage => 'Next page';

  @override
  String get mySignatureTitle => 'My signature';

  @override
  String get mySignatureScan => 'Scan from paper';

  @override
  String get mySignatureDraw => 'Draw';

  @override
  String get mySignatureInk => 'Ink colour';

  @override
  String get inkBlack => 'Black';

  @override
  String get inkBlue => 'Blue';

  @override
  String get inkOriginal => 'Original';

  @override
  String get mySignatureScanTip =>
      'Sign on white paper with a dark pen, then take a photo. Your signature is saved only on this phone.';

  @override
  String get mySignatureDrawTip =>
      'Sign with your finger in the box. Your signature is saved only on this phone.';

  @override
  String get mySignatureTakePhoto => 'Take photo';

  @override
  String get mySignatureRetake => 'Retake';

  @override
  String get mySignatureSave => 'Save signature';

  @override
  String get mySignatureBgRemoved => 'Background removed';

  @override
  String get mySignatureNotFound =>
      'Couldn\'t find a signature. Use white paper and a dark pen, and fill the frame.';

  @override
  String get mySignatureUndo => 'Undo';

  @override
  String get mySignatureClear => 'Clear';

  @override
  String get settingsSignature => 'Signature';

  @override
  String get settingsMySignature => 'My signature';

  @override
  String get settingsSignatureSaved => 'Saved';

  @override
  String get settingsSignatureNone => 'Not set';

  @override
  String get settingsSignatureDelete => 'Delete signature';

  @override
  String get settingsSignatureDeleteBody =>
      'Pages you already signed keep their signature.';

  @override
  String get modePhoto => 'Passport photo';

  @override
  String get activityPhotoSheet => 'Photo sheet';

  @override
  String get photoTitle => 'Passport photo';

  @override
  String get photoSize35x45 => '35 × 45 mm';

  @override
  String get photoSize2x2 => '2 × 2 in';

  @override
  String get photoSizeCustom => 'Custom';

  @override
  String get photoCustomTitle => 'Photo size';

  @override
  String get photoWidthMm => 'Width (mm)';

  @override
  String get photoHeightMm => 'Height (mm)';

  @override
  String get photoHint => 'Pinch to zoom · fit the face in the oval';

  @override
  String get photoTopOfHead => 'Top of head';

  @override
  String get photoChin => 'Chin';

  @override
  String get photoTakePhoto => 'Take a photo';

  @override
  String get photoFromGallery => 'Choose from gallery';

  @override
  String get photoSheetTitle => 'Print sheet';

  @override
  String get photoPaperA4 => 'A4';

  @override
  String get photoPaper4x6 => '4 × 6 in photo paper';

  @override
  String get photoCopies => 'Photos on sheet';

  @override
  String photoFull(int count) {
    return 'Full ($count)';
  }

  @override
  String get photoCutLines => 'Cut lines';

  @override
  String get photoPrintTip =>
      'Print at 100% / Actual size. Photo shops can print the 4 × 6 sheet on glossy photo paper.';

  @override
  String get photoSharePdf => 'Share PDF';

  @override
  String photoDefaultTitle(String date) {
    return 'Passport photo - $date';
  }

  @override
  String get photoStepCrop => 'Step 1 of 2 · Crop';

  @override
  String photoStepSheet(String size) {
    return 'Step 2 of 2 · $size';
  }

  @override
  String get photoSizeLabel => 'Photo size';

  @override
  String get photoRetake => 'Retake';

  @override
  String get photoMakeSheet => 'Make print sheet';

  @override
  String photoUpTo(int count) {
    return 'Up to $count photos';
  }

  @override
  String photoSheetCaption(String paper, int count) {
    return '$paper · $count photos at real size · dashed = cut lines';
  }

  @override
  String get photoPaperLabel => 'Paper';

  @override
  String get homeIdCard => 'ID Card';
}
