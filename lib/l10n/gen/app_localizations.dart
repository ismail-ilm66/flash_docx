import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Flash Dox'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get navScan;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Flash Dox'**
  String get homeTitle;

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// No description provided for @homeRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get homeRecentActivity;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search documents'**
  String get homeSearchHint;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the camera button to scan your first document, or import photos from your gallery.'**
  String get homeEmptyBody;

  /// No description provided for @homeImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get homeImport;

  /// No description provided for @homeImportGallery.
  ///
  /// In en, this message translates to:
  /// **'From gallery'**
  String get homeImportGallery;

  /// No description provided for @homeImportFiles.
  ///
  /// In en, this message translates to:
  /// **'From files'**
  String get homeImportFiles;

  /// No description provided for @modeDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get modeDocument;

  /// No description provided for @modeIdCard.
  ///
  /// In en, this message translates to:
  /// **'ID card'**
  String get modeIdCard;

  /// No description provided for @modePassport.
  ///
  /// In en, this message translates to:
  /// **'Passport'**
  String get modePassport;

  /// No description provided for @activityCreated.
  ///
  /// In en, this message translates to:
  /// **'Scanned'**
  String get activityCreated;

  /// No description provided for @activityEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get activityEdited;

  /// No description provided for @activitySharedPdf.
  ///
  /// In en, this message translates to:
  /// **'Shared as PDF'**
  String get activitySharedPdf;

  /// No description provided for @activitySharedImages.
  ///
  /// In en, this message translates to:
  /// **'Shared as images'**
  String get activitySharedImages;

  /// No description provided for @activitySavedToPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved to phone'**
  String get activitySavedToPhone;

  /// No description provided for @activityTextCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get activityTextCopied;

  /// No description provided for @activityPrintLayout.
  ///
  /// In en, this message translates to:
  /// **'Print layout created'**
  String get activityPrintLayout;

  /// No description provided for @pagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String pagesCount(int count);

  /// No description provided for @cameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get cameraTitle;

  /// No description provided for @cameraFlashOn.
  ///
  /// In en, this message translates to:
  /// **'Flash on'**
  String get cameraFlashOn;

  /// No description provided for @cameraFlashOff.
  ///
  /// In en, this message translates to:
  /// **'Flash off'**
  String get cameraFlashOff;

  /// No description provided for @cameraGuideFront.
  ///
  /// In en, this message translates to:
  /// **'Front side'**
  String get cameraGuideFront;

  /// No description provided for @cameraGuideBack.
  ///
  /// In en, this message translates to:
  /// **'Back side'**
  String get cameraGuideBack;

  /// No description provided for @cameraGuidePassport.
  ///
  /// In en, this message translates to:
  /// **'Passport data page'**
  String get cameraGuidePassport;

  /// No description provided for @cameraGuideDocument.
  ///
  /// In en, this message translates to:
  /// **'Page {n} · hold the phone flat over the page'**
  String cameraGuideDocument(int n);

  /// No description provided for @cameraDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get cameraDone;

  /// No description provided for @cameraPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access needed'**
  String get cameraPermissionTitle;

  /// No description provided for @cameraPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Flash Dox needs the camera to scan documents. You can allow it in Settings.'**
  String get cameraPermissionBody;

  /// No description provided for @cameraOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get cameraOpenSettings;

  /// No description provided for @cameraImportInstead.
  ///
  /// In en, this message translates to:
  /// **'Import instead'**
  String get cameraImportInstead;

  /// No description provided for @adjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust edges'**
  String get adjustTitle;

  /// No description provided for @adjustHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners to fit the document'**
  String get adjustHint;

  /// No description provided for @adjustAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get adjustAuto;

  /// No description provided for @adjustRotateLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get adjustRotateLeft;

  /// No description provided for @adjustRotateRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get adjustRotateRight;

  /// No description provided for @adjustRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get adjustRetake;

  /// No description provided for @adjustDeletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get adjustDeletePage;

  /// No description provided for @adjustNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get adjustNext;

  /// No description provided for @enhanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get enhanceTitle;

  /// No description provided for @enhanceBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get enhanceBrightness;

  /// No description provided for @enhanceContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get enhanceContrast;

  /// No description provided for @enhanceAppliedAll.
  ///
  /// In en, this message translates to:
  /// **'Applied to all pages'**
  String get enhanceAppliedAll;

  /// No description provided for @enhanceHoldToCompare.
  ///
  /// In en, this message translates to:
  /// **'Hold to compare'**
  String get enhanceHoldToCompare;

  /// No description provided for @enhanceDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get enhanceDone;

  /// No description provided for @enhanceReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get enhanceReset;

  /// No description provided for @filterOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// No description provided for @filterAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get filterAuto;

  /// No description provided for @filterColorBoost.
  ///
  /// In en, this message translates to:
  /// **'Color boost'**
  String get filterColorBoost;

  /// No description provided for @filterGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// No description provided for @filterIdColor.
  ///
  /// In en, this message translates to:
  /// **'ID colour'**
  String get filterIdColor;

  /// No description provided for @filterBwPrint.
  ///
  /// In en, this message translates to:
  /// **'B&W print'**
  String get filterBwPrint;

  /// No description provided for @viewerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get viewerEdit;

  /// No description provided for @viewerText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get viewerText;

  /// No description provided for @viewerPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get viewerPrint;

  /// No description provided for @viewerShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get viewerShare;

  /// No description provided for @viewerAddPages.
  ///
  /// In en, this message translates to:
  /// **'Add pages'**
  String get viewerAddPages;

  /// No description provided for @viewerRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get viewerRename;

  /// No description provided for @viewerReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder pages'**
  String get viewerReorder;

  /// No description provided for @viewerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get viewerDelete;

  /// No description provided for @viewerDeletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get viewerDeletePage;

  /// No description provided for @viewerPageOf.
  ///
  /// In en, this message translates to:
  /// **'{n} of {total}'**
  String viewerPageOf(int n, int total);

  /// No description provided for @viewerUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get viewerUntitled;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get renameTitle;

  /// No description provided for @renameHint.
  ///
  /// In en, this message translates to:
  /// **'Document name'**
  String get renameHint;

  /// No description provided for @deleteDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this document?'**
  String get deleteDocTitle;

  /// No description provided for @deleteDocBody.
  ///
  /// In en, this message translates to:
  /// **'All pages will be removed from your phone. This can\'t be undone.'**
  String get deleteDocBody;

  /// No description provided for @deletePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this page?'**
  String get deletePageTitle;

  /// No description provided for @deletePageBody.
  ///
  /// In en, this message translates to:
  /// **'The page will be removed from the document.'**
  String get deletePageBody;

  /// No description provided for @ocrTitle.
  ///
  /// In en, this message translates to:
  /// **'Extracted text'**
  String get ocrTitle;

  /// No description provided for @ocrThisPage.
  ///
  /// In en, this message translates to:
  /// **'This page'**
  String get ocrThisPage;

  /// No description provided for @ocrAllPages.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get ocrAllPages;

  /// No description provided for @ocrCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get ocrCut;

  /// No description provided for @ocrCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get ocrCopyAll;

  /// No description provided for @ocrShareTxt.
  ///
  /// In en, this message translates to:
  /// **'Share .txt'**
  String get ocrShareTxt;

  /// No description provided for @ocrCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get ocrCopied;

  /// No description provided for @ocrEmpty.
  ///
  /// In en, this message translates to:
  /// **'No text found on this page'**
  String get ocrEmpty;

  /// No description provided for @ocrWorking.
  ///
  /// In en, this message translates to:
  /// **'Reading text…'**
  String get ocrWorking;

  /// No description provided for @ocrPageSeparator.
  ///
  /// In en, this message translates to:
  /// **'--- Page {n} ---'**
  String ocrPageSeparator(int n);

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareTitle;

  /// No description provided for @shareFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get shareFormat;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get sharePdf;

  /// No description provided for @shareJpg.
  ///
  /// In en, this message translates to:
  /// **'JPG'**
  String get shareJpg;

  /// No description provided for @sharePng.
  ///
  /// In en, this message translates to:
  /// **'PNG'**
  String get sharePng;

  /// No description provided for @shareQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get shareQuality;

  /// No description provided for @shareQualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get shareQualityStandard;

  /// No description provided for @shareQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get shareQualityHigh;

  /// No description provided for @sharePageSize.
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get sharePageSize;

  /// No description provided for @sharePageA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get sharePageA4;

  /// No description provided for @sharePageLetter.
  ///
  /// In en, this message translates to:
  /// **'Letter'**
  String get sharePageLetter;

  /// No description provided for @sharePageFit.
  ///
  /// In en, this message translates to:
  /// **'Fit to image'**
  String get sharePageFit;

  /// No description provided for @shareFileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get shareFileName;

  /// No description provided for @shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// No description provided for @shareSaveToPhone.
  ///
  /// In en, this message translates to:
  /// **'Save to phone'**
  String get shareSaveToPhone;

  /// No description provided for @shareSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to phone'**
  String get shareSaved;

  /// No description provided for @sharePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get sharePreparing;

  /// No description provided for @shareWatchVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get shareWatchVideo;

  /// No description provided for @printTitle.
  ///
  /// In en, this message translates to:
  /// **'Print layout'**
  String get printTitle;

  /// No description provided for @printOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get printOutput;

  /// No description provided for @printOutputImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get printOutputImage;

  /// No description provided for @printOutputDoubleSided.
  ///
  /// In en, this message translates to:
  /// **'PDF\ndouble-sided'**
  String get printOutputDoubleSided;

  /// No description provided for @printOutputOnePage.
  ///
  /// In en, this message translates to:
  /// **'PDF\none page'**
  String get printOutputOnePage;

  /// No description provided for @printCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies per sheet'**
  String get printCopies;

  /// No description provided for @printActualSize.
  ///
  /// In en, this message translates to:
  /// **'Print at 100% / Actual size, flip on long edge.'**
  String get printActualSize;

  /// No description provided for @printShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get printShare;

  /// No description provided for @printSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get printSave;

  /// No description provided for @printNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available for this document'**
  String get printNotAvailable;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock with a short video'**
  String get unlockTitle;

  /// No description provided for @unlockBody.
  ///
  /// In en, this message translates to:
  /// **'Watch one video to unlock {feature} for this export.'**
  String unlockBody(String feature);

  /// No description provided for @unlockWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch video'**
  String get unlockWatch;

  /// No description provided for @unlockNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get unlockNotNow;

  /// No description provided for @unlockOffline.
  ///
  /// In en, this message translates to:
  /// **'Needs internet for the video. Free options still work.'**
  String get unlockOffline;

  /// No description provided for @unlockLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading video…'**
  String get unlockLoading;

  /// No description provided for @featureHighQuality.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get featureHighQuality;

  /// No description provided for @featurePng.
  ///
  /// In en, this message translates to:
  /// **'PNG export'**
  String get featurePng;

  /// No description provided for @featureAllPagesText.
  ///
  /// In en, this message translates to:
  /// **'All pages'**
  String get featureAllPagesText;

  /// No description provided for @featureMoreCopies.
  ///
  /// In en, this message translates to:
  /// **'More copies'**
  String get featureMoreCopies;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsScan.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get settingsScan;

  /// No description provided for @settingsDefaultFilter.
  ///
  /// In en, this message translates to:
  /// **'Default filter'**
  String get settingsDefaultFilter;

  /// No description provided for @settingsShare.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get settingsShare;

  /// No description provided for @settingsDefaultFormat.
  ///
  /// In en, this message translates to:
  /// **'Default format'**
  String get settingsDefaultFormat;

  /// No description provided for @settingsDefaultPageSize.
  ///
  /// In en, this message translates to:
  /// **'PDF page size'**
  String get settingsDefaultPageSize;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @settingsStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'Used by Flash Dox'**
  String get settingsStorageUsed;

  /// No description provided for @settingsClearTemp.
  ///
  /// In en, this message translates to:
  /// **'Clear temporary files'**
  String get settingsClearTemp;

  /// No description provided for @settingsClearedTemp.
  ///
  /// In en, this message translates to:
  /// **'Temporary files cleared'**
  String get settingsClearedTemp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacy;

  /// No description provided for @settingsFaq.
  ///
  /// In en, this message translates to:
  /// **'FAQ'**
  String get settingsFaq;

  /// No description provided for @settingsRate.
  ///
  /// In en, this message translates to:
  /// **'Rate Flash Dox'**
  String get settingsRate;

  /// No description provided for @settingsShareApp.
  ///
  /// In en, this message translates to:
  /// **'Share the app'**
  String get settingsShareApp;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Flash Dox · version {v}'**
  String settingsVersion(String v);

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get commonSelectAll;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @errorStorage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t write to storage'**
  String get errorStorage;

  /// No description provided for @errorImage.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t process the image'**
  String get errorImage;

  /// No description provided for @errorOcr.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read text from the image'**
  String get errorOcr;

  /// No description provided for @errorPdf.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build the PDF'**
  String get errorPdf;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get errorPermission;

  /// No description provided for @errorOffline.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get errorOffline;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Scan. Clean. Share.'**
  String get splashTagline;

  /// No description provided for @homeHeadline.
  ///
  /// In en, this message translates to:
  /// **'What are we scanning today?'**
  String get homeHeadline;

  /// No description provided for @homeDocument.
  ///
  /// In en, this message translates to:
  /// **'Docs'**
  String get homeDocument;

  /// No description provided for @homeSortLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get homeSortLatest;

  /// No description provided for @homeSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get homeSortOldest;

  /// No description provided for @homeSortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get homeSortName;

  /// No description provided for @homeSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort documents'**
  String get homeSortBy;

  /// No description provided for @homeNoResults.
  ///
  /// In en, this message translates to:
  /// **'No documents match your search'**
  String get homeNoResults;

  /// No description provided for @commonMore.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get commonMore;

  /// No description provided for @cameraFlashOnShort.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get cameraFlashOnShort;

  /// No description provided for @cameraFlashOffShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get cameraFlashOffShort;

  /// No description provided for @cameraTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get cameraTakePhoto;

  /// No description provided for @cameraReview.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review 1 page} other{Review {count} pages}}'**
  String cameraReview(int count);

  /// No description provided for @cameraRemoveLast.
  ///
  /// In en, this message translates to:
  /// **'Remove last capture'**
  String get cameraRemoveLast;

  /// No description provided for @pageOfTotal.
  ///
  /// In en, this message translates to:
  /// **'Page {n} of {total}'**
  String pageOfTotal(int n, int total);

  /// No description provided for @viewerCounter.
  ///
  /// In en, this message translates to:
  /// **'{n} / {total}'**
  String viewerCounter(int n, int total);

  /// No description provided for @viewerHoldToReorder.
  ///
  /// In en, this message translates to:
  /// **'Hold to reorder'**
  String get viewerHoldToReorder;

  /// No description provided for @dateTodayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String dateTodayAt(String time);

  /// No description provided for @dateYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String dateYesterdayAt(String time);

  /// No description provided for @ocrHint.
  ///
  /// In en, this message translates to:
  /// **'Read on your phone · works offline · you can edit before copying'**
  String get ocrHint;

  /// No description provided for @ocrTxt.
  ///
  /// In en, this message translates to:
  /// **'.txt'**
  String get ocrTxt;

  /// No description provided for @ocrPrevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get ocrPrevPage;

  /// No description provided for @ocrNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get ocrNextPage;

  /// No description provided for @shareOneFile.
  ///
  /// In en, this message translates to:
  /// **'1 file'**
  String get shareOneFile;

  /// No description provided for @shareImagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 image} other{{count} images}}'**
  String shareImagesCount(int count);

  /// No description provided for @shareQualityStandardHint.
  ///
  /// In en, this message translates to:
  /// **'Smaller file · for sharing'**
  String get shareQualityStandardHint;

  /// No description provided for @shareQualityHighHint.
  ///
  /// In en, this message translates to:
  /// **'Best for printing'**
  String get shareQualityHighHint;

  /// No description provided for @shareButtonFormat.
  ///
  /// In en, this message translates to:
  /// **'Share {format}'**
  String shareButtonFormat(String format);

  /// No description provided for @printSheetCaption.
  ///
  /// In en, this message translates to:
  /// **'A4 · cards at real size, {w} × {h} mm'**
  String printSheetCaption(String w, String h);

  /// No description provided for @printTipDuplex.
  ///
  /// In en, this message translates to:
  /// **'Print double-sided, {flip}, at {scale}. Each back lands behind its front.'**
  String printTipDuplex(String flip, String scale);

  /// No description provided for @printTipSingle.
  ///
  /// In en, this message translates to:
  /// **'Print at {scale} so cards come out at their real size.'**
  String printTipSingle(String scale);

  /// No description provided for @printTipFlip.
  ///
  /// In en, this message translates to:
  /// **'flip on long edge'**
  String get printTipFlip;

  /// No description provided for @printTipScale.
  ///
  /// In en, this message translates to:
  /// **'100% / Actual size'**
  String get printTipScale;

  /// No description provided for @printShareImage.
  ///
  /// In en, this message translates to:
  /// **'Share image'**
  String get printShareImage;

  /// No description provided for @unlockFeatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock {feature}'**
  String unlockFeatureTitle(String feature);

  /// No description provided for @unlockBodyHighQuality.
  ///
  /// In en, this message translates to:
  /// **'Watch a short video to export this file at full resolution.'**
  String get unlockBodyHighQuality;

  /// No description provided for @unlockBodyPng.
  ///
  /// In en, this message translates to:
  /// **'Watch a short video to export lossless PNG images.'**
  String get unlockBodyPng;

  /// No description provided for @unlockBodyAllPagesText.
  ///
  /// In en, this message translates to:
  /// **'Watch a short video to read the text of every page at once.'**
  String get unlockBodyAllPagesText;

  /// No description provided for @unlockBodyMoreCopies.
  ///
  /// In en, this message translates to:
  /// **'Watch a short video to fit more copies on one sheet.'**
  String get unlockBodyMoreCopies;

  /// No description provided for @unlockFreeNote.
  ///
  /// In en, this message translates to:
  /// **'Scanning, editing and standard sharing always stay free.'**
  String get unlockFreeNote;

  /// No description provided for @unlockNeedsInternet.
  ///
  /// In en, this message translates to:
  /// **'Needs internet for the video'**
  String get unlockNeedsInternet;

  /// No description provided for @settingsChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get settingsChoose;

  /// No description provided for @addFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get addFromCamera;

  /// No description provided for @backLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave Flash Dox?'**
  String get backLeaveTitle;

  /// No description provided for @backLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get backLeave;

  /// No description provided for @backStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get backStay;

  /// No description provided for @discardScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this scan?'**
  String get discardScanTitle;

  /// No description provided for @discardScanBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page will be lost.} other{{count} pages will be lost.}}'**
  String discardScanBody(int count);

  /// No description provided for @discardScan.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardScan;

  /// No description provided for @keepScanning.
  ///
  /// In en, this message translates to:
  /// **'Keep scanning'**
  String get keepScanning;

  /// No description provided for @adjustEdgesNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find the edges — drag the corners'**
  String get adjustEdgesNotFound;

  /// No description provided for @settingsShutterSound.
  ///
  /// In en, this message translates to:
  /// **'Shutter sound'**
  String get settingsShutterSound;

  /// No description provided for @settingsDefaultQuality.
  ///
  /// In en, this message translates to:
  /// **'Default quality'**
  String get settingsDefaultQuality;

  /// No description provided for @printCutGuides.
  ///
  /// In en, this message translates to:
  /// **'Cut guides'**
  String get printCutGuides;

  /// No description provided for @printSwapSides.
  ///
  /// In en, this message translates to:
  /// **'Swap front/back'**
  String get printSwapSides;

  /// No description provided for @printSheetOf.
  ///
  /// In en, this message translates to:
  /// **'Sheet {n} of {total}'**
  String printSheetOf(int n, int total);

  /// No description provided for @shareLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get shareLayout;

  /// No description provided for @shareLayoutOneImage.
  ///
  /// In en, this message translates to:
  /// **'One image (front + back)'**
  String get shareLayoutOneImage;

  /// No description provided for @shareLayoutSeparate.
  ///
  /// In en, this message translates to:
  /// **'Separate images'**
  String get shareLayoutSeparate;

  /// No description provided for @defaultDocName.
  ///
  /// In en, this message translates to:
  /// **'Flash Scan'**
  String get defaultDocName;

  /// No description provided for @cameraBlurryTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo looks blurry'**
  String get cameraBlurryTitle;

  /// No description provided for @cameraRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get cameraRetake;

  /// No description provided for @cameraKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get cameraKeep;

  /// No description provided for @cameraDark.
  ///
  /// In en, this message translates to:
  /// **'It\'s dark — turn on the flash for a sharper scan.'**
  String get cameraDark;

  /// No description provided for @cameraUnreadable.
  ///
  /// In en, this message translates to:
  /// **'That photo couldn\'t be read. Please take it again.'**
  String get cameraUnreadable;

  /// No description provided for @cameraStorageLow.
  ///
  /// In en, this message translates to:
  /// **'Your phone storage is almost full — scans may be slow.'**
  String get cameraStorageLow;

  /// No description provided for @cameraStorageFull.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage to save scans. Free up space and try again.'**
  String get cameraStorageFull;

  /// No description provided for @cameraPreparingProgress.
  ///
  /// In en, this message translates to:
  /// **'Preparing {done} of {total}…'**
  String cameraPreparingProgress(int done, int total);

  /// No description provided for @settingsMagneticEdges.
  ///
  /// In en, this message translates to:
  /// **'Magnetic edges'**
  String get settingsMagneticEdges;

  /// No description provided for @printQualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard · 300 DPI'**
  String get printQualityStandard;

  /// No description provided for @printQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High · 600 DPI'**
  String get printQualityHigh;

  /// No description provided for @cameraHintDocument.
  ///
  /// In en, this message translates to:
  /// **'Hold steady · edges are found automatically'**
  String get cameraHintDocument;

  /// No description provided for @cameraHintCard.
  ///
  /// In en, this message translates to:
  /// **'Fit the card in the frame · move back if it\'s blurry'**
  String get cameraHintCard;

  /// No description provided for @cameraCardBlurry.
  ///
  /// In en, this message translates to:
  /// **'Card looks blurry'**
  String get cameraCardBlurry;

  /// No description provided for @enhanceAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get enhanceAdjust;

  /// No description provided for @enhanceAllPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{All {count} pages}}'**
  String enhanceAllPages(int count);

  /// No description provided for @enhanceZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get enhanceZoomIn;

  /// No description provided for @enhanceZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get enhanceZoomOut;

  /// No description provided for @sharePreparingPages.
  ///
  /// In en, this message translates to:
  /// **'Preparing… {done}/{total} pages'**
  String sharePreparingPages(int done, int total);

  /// No description provided for @homeTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get homeTools;

  /// No description provided for @toolPassportPhoto.
  ///
  /// In en, this message translates to:
  /// **'Passport photo'**
  String get toolPassportPhoto;

  /// No description provided for @toolSign.
  ///
  /// In en, this message translates to:
  /// **'Sign document'**
  String get toolSign;

  /// No description provided for @toolShrinkPdf.
  ///
  /// In en, this message translates to:
  /// **'Shrink PDF'**
  String get toolShrinkPdf;

  /// No description provided for @toolExtractText.
  ///
  /// In en, this message translates to:
  /// **'Extract text'**
  String get toolExtractText;

  /// No description provided for @pickDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a document'**
  String get pickDocumentTitle;

  /// No description provided for @pickDocumentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No documents yet. Scan one first.'**
  String get pickDocumentEmpty;

  /// No description provided for @shareMaxSize.
  ///
  /// In en, this message translates to:
  /// **'Max file size'**
  String get shareMaxSize;

  /// No description provided for @shareMaxSizeHint.
  ///
  /// In en, this message translates to:
  /// **'For upload limits on forms and portals'**
  String get shareMaxSizeHint;

  /// No description provided for @maxSizeNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get maxSizeNoLimit;

  /// No description provided for @maxSizeUnder.
  ///
  /// In en, this message translates to:
  /// **'Under {size}'**
  String maxSizeUnder(String size);

  /// No description provided for @maxSizeBody.
  ///
  /// In en, this message translates to:
  /// **'The PDF is shrunk until it fits. Use this when a form or portal limits the upload size.'**
  String get maxSizeBody;

  /// No description provided for @maxSizeNoteOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get maxSizeNoteOriginal;

  /// No description provided for @maxSizeNote1mb.
  ///
  /// In en, this message translates to:
  /// **'Email and most portals'**
  String get maxSizeNote1mb;

  /// No description provided for @maxSizeNote500kb.
  ///
  /// In en, this message translates to:
  /// **'Common form limit'**
  String get maxSizeNote500kb;

  /// No description provided for @maxSizeNote200kb.
  ///
  /// In en, this message translates to:
  /// **'Small text may get soft'**
  String get maxSizeNote200kb;

  /// No description provided for @maxSizeTagBest.
  ///
  /// In en, this message translates to:
  /// **'Best'**
  String get maxSizeTagBest;

  /// No description provided for @maxSizeTagSharp.
  ///
  /// In en, this message translates to:
  /// **'Sharp'**
  String get maxSizeTagSharp;

  /// No description provided for @maxSizeTagGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get maxSizeTagGood;

  /// No description provided for @maxSizeTagReadable.
  ///
  /// In en, this message translates to:
  /// **'Readable'**
  String get maxSizeTagReadable;

  /// No description provided for @maxSizeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get maxSizeCustom;

  /// No description provided for @maxSizeCustomHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 300'**
  String get maxSizeCustomHint;

  /// No description provided for @maxSizeKb.
  ///
  /// In en, this message translates to:
  /// **'KB'**
  String get maxSizeKb;

  /// No description provided for @shareReadySize.
  ///
  /// In en, this message translates to:
  /// **'Ready · {size}'**
  String shareReadySize(String size);

  /// No description provided for @shareHardToRead.
  ///
  /// In en, this message translates to:
  /// **'Small text may be hard to read.'**
  String get shareHardToRead;

  /// No description provided for @shareNeedsGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Can\'t fit in colour. Make it black and white to fit?'**
  String get shareNeedsGrayscale;

  /// No description provided for @shareMakeGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Black and white'**
  String get shareMakeGrayscale;

  /// No description provided for @shareCantFit.
  ///
  /// In en, this message translates to:
  /// **'Can\'t get under {size} without making it unreadable. Try fewer pages or black and white.'**
  String shareCantFit(String size);

  /// No description provided for @shareShrinking.
  ///
  /// In en, this message translates to:
  /// **'Making it fit…'**
  String get shareShrinking;

  /// No description provided for @folderAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get folderAll;

  /// No description provided for @folderBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get folderBills;

  /// No description provided for @folderIds.
  ///
  /// In en, this message translates to:
  /// **'IDs'**
  String get folderIds;

  /// No description provided for @folderEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get folderEducation;

  /// No description provided for @folderReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get folderReceipts;

  /// No description provided for @folderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get folderOther;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {folder} yet'**
  String folderEmpty(String folder);

  /// No description provided for @smartLooksLike.
  ///
  /// In en, this message translates to:
  /// **'Looks like {kind}'**
  String smartLooksLike(String kind);

  /// No description provided for @smartRenameTo.
  ///
  /// In en, this message translates to:
  /// **'Rename to “{title}” · {folder}'**
  String smartRenameTo(String title, String folder);

  /// No description provided for @smartApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get smartApply;

  /// No description provided for @smartDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss suggestion'**
  String get smartDismiss;

  /// No description provided for @menuMoveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get menuMoveToFolder;

  /// No description provided for @movedToFolder.
  ///
  /// In en, this message translates to:
  /// **'Moved to {folder}'**
  String movedToFolder(String folder);

  /// No description provided for @sidesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 side} other{{count} sides}}'**
  String sidesCount(int count);

  /// No description provided for @activitySigned.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get activitySigned;

  /// No description provided for @viewerSign.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get viewerSign;

  /// No description provided for @signTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign document'**
  String get signTitle;

  /// No description provided for @signHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to move · drag the corner to resize'**
  String get signHint;

  /// No description provided for @signInk.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get signInk;

  /// No description provided for @signChange.
  ///
  /// In en, this message translates to:
  /// **'Change signature'**
  String get signChange;

  /// No description provided for @signAddDate.
  ///
  /// In en, this message translates to:
  /// **'Add date'**
  String get signAddDate;

  /// No description provided for @signAddSignature.
  ///
  /// In en, this message translates to:
  /// **'Add signature'**
  String get signAddSignature;

  /// No description provided for @signRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get signRemove;

  /// No description provided for @signPrevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get signPrevPage;

  /// No description provided for @signNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get signNextPage;

  /// No description provided for @mySignatureTitle.
  ///
  /// In en, this message translates to:
  /// **'My signature'**
  String get mySignatureTitle;

  /// No description provided for @mySignatureScan.
  ///
  /// In en, this message translates to:
  /// **'Scan from paper'**
  String get mySignatureScan;

  /// No description provided for @mySignatureDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get mySignatureDraw;

  /// No description provided for @mySignatureInk.
  ///
  /// In en, this message translates to:
  /// **'Ink colour'**
  String get mySignatureInk;

  /// No description provided for @inkBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get inkBlack;

  /// No description provided for @inkBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get inkBlue;

  /// No description provided for @inkOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get inkOriginal;

  /// No description provided for @mySignatureScanTip.
  ///
  /// In en, this message translates to:
  /// **'Sign on white paper with a dark pen, then take a photo. Your signature is saved only on this phone.'**
  String get mySignatureScanTip;

  /// No description provided for @mySignatureDrawTip.
  ///
  /// In en, this message translates to:
  /// **'Sign with your finger in the box. Your signature is saved only on this phone.'**
  String get mySignatureDrawTip;

  /// No description provided for @mySignatureTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get mySignatureTakePhoto;

  /// No description provided for @mySignatureRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get mySignatureRetake;

  /// No description provided for @mySignatureSave.
  ///
  /// In en, this message translates to:
  /// **'Save signature'**
  String get mySignatureSave;

  /// No description provided for @mySignatureBgRemoved.
  ///
  /// In en, this message translates to:
  /// **'Background removed'**
  String get mySignatureBgRemoved;

  /// No description provided for @mySignatureNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find a signature. Use white paper and a dark pen, and fill the frame.'**
  String get mySignatureNotFound;

  /// No description provided for @mySignatureUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get mySignatureUndo;

  /// No description provided for @mySignatureClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get mySignatureClear;

  /// No description provided for @settingsSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get settingsSignature;

  /// No description provided for @settingsMySignature.
  ///
  /// In en, this message translates to:
  /// **'My signature'**
  String get settingsMySignature;

  /// No description provided for @settingsSignatureSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get settingsSignatureSaved;

  /// No description provided for @settingsSignatureNone.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get settingsSignatureNone;

  /// No description provided for @settingsSignatureDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete signature'**
  String get settingsSignatureDelete;

  /// No description provided for @settingsSignatureDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Pages you already signed keep their signature.'**
  String get settingsSignatureDeleteBody;

  /// No description provided for @modePhoto.
  ///
  /// In en, this message translates to:
  /// **'Passport photo'**
  String get modePhoto;

  /// No description provided for @activityPhotoSheet.
  ///
  /// In en, this message translates to:
  /// **'Photo sheet'**
  String get activityPhotoSheet;

  /// No description provided for @photoTitle.
  ///
  /// In en, this message translates to:
  /// **'Passport photo'**
  String get photoTitle;

  /// No description provided for @photoSize35x45.
  ///
  /// In en, this message translates to:
  /// **'35 × 45 mm'**
  String get photoSize35x45;

  /// No description provided for @photoSize2x2.
  ///
  /// In en, this message translates to:
  /// **'2 × 2 in'**
  String get photoSize2x2;

  /// No description provided for @photoSizeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get photoSizeCustom;

  /// No description provided for @photoCustomTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo size'**
  String get photoCustomTitle;

  /// No description provided for @photoWidthMm.
  ///
  /// In en, this message translates to:
  /// **'Width (mm)'**
  String get photoWidthMm;

  /// No description provided for @photoHeightMm.
  ///
  /// In en, this message translates to:
  /// **'Height (mm)'**
  String get photoHeightMm;

  /// No description provided for @photoHint.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom · fit the face in the oval'**
  String get photoHint;

  /// No description provided for @photoTopOfHead.
  ///
  /// In en, this message translates to:
  /// **'Top of head'**
  String get photoTopOfHead;

  /// No description provided for @photoChin.
  ///
  /// In en, this message translates to:
  /// **'Chin'**
  String get photoChin;

  /// No description provided for @photoTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get photoTakePhoto;

  /// No description provided for @photoFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get photoFromGallery;

  /// No description provided for @photoSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Print sheet'**
  String get photoSheetTitle;

  /// No description provided for @photoPaperA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get photoPaperA4;

  /// No description provided for @photoPaper4x6.
  ///
  /// In en, this message translates to:
  /// **'4 × 6 in photo paper'**
  String get photoPaper4x6;

  /// No description provided for @photoCopies.
  ///
  /// In en, this message translates to:
  /// **'Photos on sheet'**
  String get photoCopies;

  /// No description provided for @photoFull.
  ///
  /// In en, this message translates to:
  /// **'Full ({count})'**
  String photoFull(int count);

  /// No description provided for @photoCutLines.
  ///
  /// In en, this message translates to:
  /// **'Cut lines'**
  String get photoCutLines;

  /// No description provided for @photoPrintTip.
  ///
  /// In en, this message translates to:
  /// **'Print at 100% / Actual size. Photo shops can print the 4 × 6 sheet on glossy photo paper.'**
  String get photoPrintTip;

  /// No description provided for @photoSharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF'**
  String get photoSharePdf;

  /// No description provided for @photoDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Passport photo - {date}'**
  String photoDefaultTitle(String date);

  /// No description provided for @photoStepCrop.
  ///
  /// In en, this message translates to:
  /// **'Step 1 of 2 · Crop'**
  String get photoStepCrop;

  /// No description provided for @photoStepSheet.
  ///
  /// In en, this message translates to:
  /// **'Step 2 of 2 · {size}'**
  String photoStepSheet(String size);

  /// No description provided for @photoSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo size'**
  String get photoSizeLabel;

  /// No description provided for @photoRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get photoRetake;

  /// No description provided for @photoMakeSheet.
  ///
  /// In en, this message translates to:
  /// **'Make print sheet'**
  String get photoMakeSheet;

  /// No description provided for @photoUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {count} photos'**
  String photoUpTo(int count);

  /// No description provided for @photoSheetCaption.
  ///
  /// In en, this message translates to:
  /// **'{paper} · {count} photos at real size · dashed = cut lines'**
  String photoSheetCaption(String paper, int count);

  /// No description provided for @photoPaperLabel.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get photoPaperLabel;

  /// No description provided for @homeIdCard.
  ///
  /// In en, this message translates to:
  /// **'ID Card'**
  String get homeIdCard;

  /// No description provided for @folderOffice.
  ///
  /// In en, this message translates to:
  /// **'Office'**
  String get folderOffice;

  /// No description provided for @cameraHintPassport.
  ///
  /// In en, this message translates to:
  /// **'Fit the open data page in the frame'**
  String get cameraHintPassport;

  /// No description provided for @cameraHintPassportPhoto.
  ///
  /// In en, this message translates to:
  /// **'Plain wall behind · face the camera · even light'**
  String get cameraHintPassportPhoto;

  /// No description provided for @cameraHintSignature.
  ///
  /// In en, this message translates to:
  /// **'Sign on white paper · fill the frame'**
  String get cameraHintSignature;

  /// No description provided for @cameraHintExtractText.
  ///
  /// In en, this message translates to:
  /// **'Hold flat · text should fill the frame'**
  String get cameraHintExtractText;

  /// No description provided for @photoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this photo. Take it again.'**
  String get photoLoadFailed;

  /// No description provided for @printSheetN.
  ///
  /// In en, this message translates to:
  /// **'Sheet {n}'**
  String printSheetN(int n);

  /// No description provided for @printImageCaption.
  ///
  /// In en, this message translates to:
  /// **'Image {w} × {h} mm · cards at real size'**
  String printImageCaption(String w, String h);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
