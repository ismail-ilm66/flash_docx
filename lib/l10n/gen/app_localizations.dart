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

  /// No description provided for @modeSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get modeSingle;

  /// No description provided for @modeBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get modeBatch;

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

  /// No description provided for @cameraGuideSingle.
  ///
  /// In en, this message translates to:
  /// **'Fit the document in the frame'**
  String get cameraGuideSingle;

  /// No description provided for @cameraGuideBatch.
  ///
  /// In en, this message translates to:
  /// **'Page {n}'**
  String cameraGuideBatch(int n);

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
  /// **'Rotate left'**
  String get adjustRotateLeft;

  /// No description provided for @adjustRotateRight.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get adjustRotateRight;

  /// No description provided for @adjustRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get adjustRetake;

  /// No description provided for @adjustDeletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
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

  /// No description provided for @enhanceApplyAll.
  ///
  /// In en, this message translates to:
  /// **'Apply to all pages'**
  String get enhanceApplyAll;

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
  /// **'High quality'**
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
  /// **'Double-sided PDF'**
  String get printOutputDoubleSided;

  /// No description provided for @printOutputOnePage.
  ///
  /// In en, this message translates to:
  /// **'One-page PDF'**
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
  /// **'High quality export'**
  String get featureHighQuality;

  /// No description provided for @featurePng.
  ///
  /// In en, this message translates to:
  /// **'PNG export'**
  String get featurePng;

  /// No description provided for @featureAllPagesText.
  ///
  /// In en, this message translates to:
  /// **'Text from all pages'**
  String get featureAllPagesText;

  /// No description provided for @featureMoreCopies.
  ///
  /// In en, this message translates to:
  /// **'More copies per sheet'**
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
  /// **'Scan'**
  String get settingsScan;

  /// No description provided for @settingsDefaultFilter.
  ///
  /// In en, this message translates to:
  /// **'Default filter'**
  String get settingsDefaultFilter;

  /// No description provided for @settingsDefaultMode.
  ///
  /// In en, this message translates to:
  /// **'Default scan mode'**
  String get settingsDefaultMode;

  /// No description provided for @settingsShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get settingsShare;

  /// No description provided for @settingsDefaultFormat.
  ///
  /// In en, this message translates to:
  /// **'Default format'**
  String get settingsDefaultFormat;

  /// No description provided for @settingsDefaultPageSize.
  ///
  /// In en, this message translates to:
  /// **'Default page size'**
  String get settingsDefaultPageSize;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @settingsStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'Space used by scans'**
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
  /// **'Share Flash Dox'**
  String get settingsShareApp;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {v}'**
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
