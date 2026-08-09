import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Application display name.
  ///
  /// In en, this message translates to:
  /// **'DeOptiDownloader'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Fountain-coded QR file transfer over light'**
  String get tagline;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @sendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a file over light'**
  String get sendTitle;

  /// No description provided for @receiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive from a screen'**
  String get receiveTitle;

  /// No description provided for @sendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a file or paste text — the app streams it as an endless series of QR codes.'**
  String get sendSubtitle;

  /// No description provided for @receiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a sender’s screen — the app reconstructs the file from the QR stream.'**
  String get receiveSubtitle;

  /// No description provided for @privacyNote.
  ///
  /// In en, this message translates to:
  /// **'Optical only: no network path is used between the devices. Without a password the stream is readable by any camera pointed at it.'**
  String get privacyNote;

  /// No description provided for @pickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a file'**
  String get pickFile;

  /// No description provided for @pasteSnippet.
  ///
  /// In en, this message translates to:
  /// **'Paste a text snippet'**
  String get pasteSnippet;

  /// No description provided for @fileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'File exceeds the 64 MB optical transfer limit.'**
  String get fileTooLarge;

  /// No description provided for @fileName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fileName;

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fileSize;

  /// No description provided for @fileType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get fileType;

  /// No description provided for @snippetHint.
  ///
  /// In en, this message translates to:
  /// **'Paste or type the text you want to send…'**
  String get snippetHint;

  /// No description provided for @snippetEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter some text first.'**
  String get snippetEmpty;

  /// No description provided for @encryption.
  ///
  /// In en, this message translates to:
  /// **'Encrypt with a password'**
  String get encryption;

  /// No description provided for @encryptionHint.
  ///
  /// In en, this message translates to:
  /// **'Authenticated encryption (XChaCha20-Poly1305). The receiver must enter the same password.'**
  String get encryptionHint;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Required by the receiver to decode the stream.'**
  String get passwordHint;

  /// No description provided for @startStream.
  ///
  /// In en, this message translates to:
  /// **'Start streaming'**
  String get startStream;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @framesPerSecond.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get framesPerSecond;

  /// No description provided for @frameSize.
  ///
  /// In en, this message translates to:
  /// **'Frame size'**
  String get frameSize;

  /// No description provided for @frameSizeHint.
  ///
  /// In en, this message translates to:
  /// **'Total bytes per QR frame; larger frames move more data but need a bigger QR.'**
  String get frameSizeHint;

  /// No description provided for @qrSize.
  ///
  /// In en, this message translates to:
  /// **'QR size'**
  String get qrSize;

  /// No description provided for @streaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get streaming;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @waitingForReceiver.
  ///
  /// In en, this message translates to:
  /// **'Hold the receiver’s camera to this screen.'**
  String get waitingForReceiver;

  /// No description provided for @framesSent.
  ///
  /// In en, this message translates to:
  /// **'Frames sent'**
  String get framesSent;

  /// No description provided for @session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// No description provided for @sourceBlocks.
  ///
  /// In en, this message translates to:
  /// **'Source blocks (K)'**
  String get sourceBlocks;

  /// No description provided for @blockSize.
  ///
  /// In en, this message translates to:
  /// **'Block size'**
  String get blockSize;

  /// No description provided for @qrVersion.
  ///
  /// In en, this message translates to:
  /// **'QR version'**
  String get qrVersion;

  /// No description provided for @elapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get elapsed;

  /// No description provided for @suggestLowerSettings.
  ///
  /// In en, this message translates to:
  /// **'If the receiver cannot lock on, lower the frame rate and frame size.'**
  String get suggestLowerSettings;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No camera is available on this device. On desktop you can receive in a browser instead.'**
  String get cameraUnavailable;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission was denied. Enable it in system settings to receive.'**
  String get cameraPermissionDenied;

  /// No description provided for @waitingForSender.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the sender’s screen…'**
  String get waitingForSender;

  /// No description provided for @pointCamera.
  ///
  /// In en, this message translates to:
  /// **'Keep the QR code inside the frame. A stream locks on automatically once frames are decoded.'**
  String get pointCamera;

  /// No description provided for @noSignalTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing happening?'**
  String get noSignalTitle;

  /// No description provided for @noSignalBody.
  ///
  /// In en, this message translates to:
  /// **'Make sure the sender is streaming. If it still fails, try sender settings of 24 fps and 1465-byte frames.'**
  String get noSignalBody;

  /// No description provided for @progressFrames.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get progressFrames;

  /// No description provided for @receiverLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked to stream'**
  String get receiverLocked;

  /// No description provided for @transferMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get transferMode;

  /// No description provided for @complete.
  ///
  /// In en, this message translates to:
  /// **'Transfer complete'**
  String get complete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @receiveAgain.
  ///
  /// In en, this message translates to:
  /// **'Receive again'**
  String get receiveAgain;

  /// No description provided for @backHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backHome;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'This transfer is encrypted'**
  String get enterPassword;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password. Try again.'**
  String get wrongPassword;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @selfTest.
  ///
  /// In en, this message translates to:
  /// **'Run Rust self-test'**
  String get selfTest;

  /// No description provided for @selfTestPass.
  ///
  /// In en, this message translates to:
  /// **'Self-test passed: pack → send → receive → unpack round trip OK.'**
  String get selfTestPass;

  /// No description provided for @selfTestFail.
  ///
  /// In en, this message translates to:
  /// **'Self-test failed:'**
  String get selfTestFail;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'The Rust core handles fountain coding, container integrity, session manifests and QR codecs. Flutter provides sending and camera receiving on supported native and web targets.'**
  String get aboutBody;

  /// No description provided for @unsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'This platform is not supported for camera capture yet.'**
  String get unsupportedPlatform;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @manifestSetup.
  ///
  /// In en, this message translates to:
  /// **'Setup QR'**
  String get manifestSetup;

  /// No description provided for @manifestScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this first to preview the transfer — data frames follow automatically.'**
  String get manifestScanHint;

  /// No description provided for @manifestIncoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get manifestIncoming;

  /// No description provided for @manifestEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get manifestEncrypted;

  /// No description provided for @streamStarting.
  ///
  /// In en, this message translates to:
  /// **'Streaming starts in a moment…'**
  String get streamStarting;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeHint.
  ///
  /// In en, this message translates to:
  /// **'Material Design 3 palettes and shape tokens apply across the interface.'**
  String get themeHint;

  /// No description provided for @colorSpec.
  ///
  /// In en, this message translates to:
  /// **'Color specification'**
  String get colorSpec;

  /// No description provided for @colorSpecIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colorSpecIndigo;

  /// No description provided for @colorSpecCyan.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get colorSpecCyan;

  /// No description provided for @colorSpecEmerald.
  ///
  /// In en, this message translates to:
  /// **'Emerald'**
  String get colorSpecEmerald;

  /// No description provided for @colorSpecViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get colorSpecViolet;

  /// No description provided for @colorSpecSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get colorSpecSunset;

  /// No description provided for @colorSpecNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get colorSpecNeutral;

  /// No description provided for @colorStyle.
  ///
  /// In en, this message translates to:
  /// **'Color style'**
  String get colorStyle;

  /// No description provided for @colorStyleTonalSpot.
  ///
  /// In en, this message translates to:
  /// **'Tonal spot'**
  String get colorStyleTonalSpot;

  /// No description provided for @colorStyleExpressive.
  ///
  /// In en, this message translates to:
  /// **'Expressive'**
  String get colorStyleExpressive;

  /// No description provided for @colorStyleFidelity.
  ///
  /// In en, this message translates to:
  /// **'Fidelity'**
  String get colorStyleFidelity;

  /// No description provided for @colorStyleVibrant.
  ///
  /// In en, this message translates to:
  /// **'Vibrant'**
  String get colorStyleVibrant;

  /// No description provided for @colorStyleNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get colorStyleNeutral;

  /// No description provided for @colorStyleMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get colorStyleMonochrome;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @themeIndigoLight.
  ///
  /// In en, this message translates to:
  /// **'Indigo (Light)'**
  String get themeIndigoLight;

  /// No description provided for @themeIndigoDark.
  ///
  /// In en, this message translates to:
  /// **'Indigo (Dark)'**
  String get themeIndigoDark;

  /// No description provided for @themeAmoled.
  ///
  /// In en, this message translates to:
  /// **'AMOLED Dark'**
  String get themeAmoled;

  /// No description provided for @themeAmoledHint.
  ///
  /// In en, this message translates to:
  /// **'Pure-black surfaces for OLED screens.'**
  String get themeAmoledHint;

  /// No description provided for @themeViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet (Expressive)'**
  String get themeViolet;

  /// No description provided for @themeMidnight.
  ///
  /// In en, this message translates to:
  /// **'Midnight (Fidelity)'**
  String get themeMidnight;

  /// No description provided for @themeSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset (Vibrant)'**
  String get themeSunset;

  /// No description provided for @themeMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get themeMonochrome;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get wallpaper;

  /// No description provided for @wallpaperNone.
  ///
  /// In en, this message translates to:
  /// **'No background'**
  String get wallpaperNone;

  /// No description provided for @wallpaperNoneHint.
  ///
  /// In en, this message translates to:
  /// **'Plain theme surfaces, no image behind the UI.'**
  String get wallpaperNoneHint;

  /// No description provided for @wallpaperBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Wallpapers'**
  String get wallpaperBuiltin;

  /// No description provided for @wallpaperCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom image'**
  String get wallpaperCustom;

  /// No description provided for @wallpaperCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a photo from your gallery as the background.'**
  String get wallpaperCustomHint;

  /// No description provided for @wallpaperBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get wallpaperBlur;

  /// No description provided for @wallpaperBlurHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to soften the background behind the interface.'**
  String get wallpaperBlurHint;

  /// No description provided for @wallpaperPick.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get wallpaperPick;

  /// No description provided for @wallpaperRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove custom image'**
  String get wallpaperRemove;

  /// No description provided for @jrc.
  ///
  /// In en, this message translates to:
  /// **'Judge-recoverable (JRC)'**
  String get jrc;

  /// No description provided for @jrcHint.
  ///
  /// In en, this message translates to:
  /// **'Pack with a designated judge’s public key. Any camera sees only a hiding commitment; only the judge can recover the file.'**
  String get jrcHint;

  /// No description provided for @judgePublicKey.
  ///
  /// In en, this message translates to:
  /// **'Judge public key'**
  String get judgePublicKey;

  /// No description provided for @judgePublicKeyHint.
  ///
  /// In en, this message translates to:
  /// **'64 hex characters of the judge’s X25519 public key.'**
  String get judgePublicKeyHint;

  /// No description provided for @judgePublicKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The judge public key must be exactly 64 hex characters.'**
  String get judgePublicKeyInvalid;

  /// No description provided for @generateJudgeKey.
  ///
  /// In en, this message translates to:
  /// **'Generate a judge key'**
  String get generateJudgeKey;

  /// No description provided for @generateJudgeKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Creates a fresh keypair you can share with a sender.'**
  String get generateJudgeKeyHint;

  /// No description provided for @judgeSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Judge secret key'**
  String get judgeSecretKey;

  /// No description provided for @judgeSecretKeyHint.
  ///
  /// In en, this message translates to:
  /// **'64 hex characters of the judge’s X25519 secret key.'**
  String get judgeSecretKeyHint;

  /// No description provided for @judgeSecretKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'The judge secret key must be exactly 64 hex characters.'**
  String get judgeSecretKeyInvalid;

  /// No description provided for @enterJudgeKey.
  ///
  /// In en, this message translates to:
  /// **'This transfer is judge-recoverable'**
  String get enterJudgeKey;

  /// No description provided for @enterJudgeKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Only the designated judge can recover this file. Enter the matching secret key.'**
  String get enterJudgeKeyBody;

  /// No description provided for @wrongJudgeKey.
  ///
  /// In en, this message translates to:
  /// **'Wrong judge key. Try again.'**
  String get wrongJudgeKey;

  /// No description provided for @judgeKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Judge key copied.'**
  String get judgeKeyCopied;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @restoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get restoreDefaults;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
