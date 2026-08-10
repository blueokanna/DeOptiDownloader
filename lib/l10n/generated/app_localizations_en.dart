// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DeOptiDownloader';

  @override
  String get tagline => 'Fountain-coded QR file transfer over light';

  @override
  String get send => 'Send';

  @override
  String get receive => 'Receive';

  @override
  String get sendTitle => 'Send a file over light';

  @override
  String get receiveTitle => 'Receive from a screen';

  @override
  String get sendSubtitle =>
      'Pick a file or paste text — the app streams it as an endless series of QR codes.';

  @override
  String get receiveSubtitle =>
      'Point your camera at a sender’s screen — the app reconstructs the file from the QR stream.';

  @override
  String get privacyNote =>
      'Optical only: no network path is used between the devices. Without a password the stream is readable by any camera pointed at it.';

  @override
  String get pickFile => 'Pick a file';

  @override
  String get pasteSnippet => 'Paste a text snippet';

  @override
  String get fileTooLarge => 'File exceeds the 64 MB optical transfer limit.';

  @override
  String get fileName => 'Name';

  @override
  String get fileSize => 'Size';

  @override
  String get fileType => 'Type';

  @override
  String get snippetHint => 'Paste or type the text you want to send…';

  @override
  String get snippetEmpty => 'Enter some text first.';

  @override
  String get encryption => 'Encrypt with a password';

  @override
  String get encryptionHint =>
      'Authenticated encryption (XChaCha20-Poly1305). The receiver must enter the same password.';

  @override
  String get password => 'Password';

  @override
  String get passwordHint => 'Required by the receiver to decode the stream.';

  @override
  String get startStream => 'Start streaming';

  @override
  String get stop => 'Stop';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get settings => 'Settings';

  @override
  String get framesPerSecond => 'Frame rate';

  @override
  String get symbolRate => 'QR symbol rate';

  @override
  String get symbolsPerSecond => 'symbols/s';

  @override
  String get symbolRateHint =>
      'New QR codes per second, independent of the screen refresh rate. Lower keeps each QR on screen longer so the receiver can lock on more reliably.';

  @override
  String get dwellPeriods => 'Dwell (repeat)';

  @override
  String get displayPeriods => 'display periods';

  @override
  String get dwellHint =>
      'How many display periods each QR stays on screen. Repeating the same symbol gives a 5–10 fps receiver several stable reads.';

  @override
  String get frameSize => 'Frame size';

  @override
  String get frameSizeHint =>
      'Total bytes per QR frame. Auto scores candidate sizes and picks the one with the best estimated throughput; larger frames move more data but need a bigger, denser QR.';

  @override
  String get qrSize => 'QR size';

  @override
  String get streaming => 'Streaming';

  @override
  String get paused => 'Paused';

  @override
  String get waitingForReceiver => 'Hold the receiver’s camera to this screen.';

  @override
  String get framesSent => 'Frames sent';

  @override
  String get session => 'Session';

  @override
  String get sourceBlocks => 'Source blocks (K)';

  @override
  String get blockSize => 'Block size';

  @override
  String get qrVersion => 'QR version';

  @override
  String get elapsed => 'Elapsed';

  @override
  String get suggestLowerSettings =>
      'If the receiver cannot lock on, lower the frame rate and frame size.';

  @override
  String get cameraUnavailable =>
      'No camera is available on this device. On desktop you can receive in a browser instead.';

  @override
  String get cameraPermissionDenied =>
      'Camera permission was denied. Enable it in system settings to receive.';

  @override
  String get waitingForSender => 'Point the camera at the sender’s screen…';

  @override
  String get pointCamera =>
      'Keep the QR code inside the frame. A stream locks on automatically once frames are decoded.';

  @override
  String get noSignalTitle => 'Nothing happening?';

  @override
  String get noSignalBody =>
      'Keep the whole QR code and its white border inside the viewfinder, avoiding glare, obstructions, and low screen brightness.';

  @override
  String get progressFrames => 'Frames';

  @override
  String get receiverLocked => 'Locked to stream';

  @override
  String get transferMode => 'Mode';

  @override
  String get complete => 'Transfer complete';

  @override
  String get save => 'Save';

  @override
  String get share => 'Share';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get receiveAgain => 'Receive again';

  @override
  String get backHome => 'Back to home';

  @override
  String get enterPassword => 'This transfer is encrypted';

  @override
  String get wrongPassword => 'Wrong password. Try again.';

  @override
  String get confirm => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get selfTest => 'Run Rust self-test';

  @override
  String get selfTestPass =>
      'Self-test passed: pack → send → receive → unpack round trip OK.';

  @override
  String get selfTestFail => 'Self-test failed:';

  @override
  String get about => 'About';

  @override
  String get aboutBody =>
      'The Rust core handles fountain coding, container integrity, session manifests and QR codecs. Flutter provides sending and camera receiving on supported native and web targets.';

  @override
  String get unsupportedPlatform =>
      'This platform is not supported for camera capture yet.';

  @override
  String get optional => 'Optional';

  @override
  String get manifestSetup => 'Setup QR';

  @override
  String get manifestScanHint =>
      'Scan this first to preview the transfer — data frames follow automatically.';

  @override
  String get manifestIncoming => 'Incoming';

  @override
  String get manifestEncrypted => 'Encrypted';

  @override
  String get streamStarting => 'Streaming starts in a moment…';

  @override
  String get theme => 'Theme';

  @override
  String get themeHint =>
      'Material Design 3 palettes and shape tokens apply across the interface.';

  @override
  String get colorSpec => 'Color specification';

  @override
  String get colorSpecIndigo => 'Indigo';

  @override
  String get colorSpecCyan => 'Cyan';

  @override
  String get colorSpecEmerald => 'Emerald';

  @override
  String get colorSpecViolet => 'Violet';

  @override
  String get colorSpecSunset => 'Sunset';

  @override
  String get colorSpecNeutral => 'Neutral';

  @override
  String get colorStyle => 'Color style';

  @override
  String get colorStyleTonalSpot => 'Tonal spot';

  @override
  String get colorStyleExpressive => 'Expressive';

  @override
  String get colorStyleFidelity => 'Fidelity';

  @override
  String get colorStyleVibrant => 'Vibrant';

  @override
  String get colorStyleNeutral => 'Neutral';

  @override
  String get colorStyleMonochrome => 'Monochrome';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get themeModeSystem => 'Follow system';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get themeIndigoLight => 'Indigo (Light)';

  @override
  String get themeIndigoDark => 'Indigo (Dark)';

  @override
  String get themeAmoled => 'AMOLED Dark';

  @override
  String get themeAmoledHint => 'Pure-black surfaces for OLED screens.';

  @override
  String get themeViolet => 'Violet (Expressive)';

  @override
  String get themeMidnight => 'Midnight (Fidelity)';

  @override
  String get themeSunset => 'Sunset (Vibrant)';

  @override
  String get themeMonochrome => 'Monochrome';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get wallpaper => 'Wallpaper';

  @override
  String get wallpaperNone => 'No background';

  @override
  String get wallpaperNoneHint =>
      'Plain theme surfaces, no image behind the UI.';

  @override
  String get wallpaperBuiltin => 'Wallpapers';

  @override
  String get wallpaperCustom => 'Custom image';

  @override
  String get wallpaperCustomHint =>
      'Pick a photo from your gallery as the background.';

  @override
  String get wallpaperBlur => 'Blur';

  @override
  String get wallpaperBlurHint =>
      'Drag to soften the background behind the interface.';

  @override
  String get wallpaperPick => 'Choose image';

  @override
  String get wallpaperRemove => 'Remove custom image';

  @override
  String get jrc => 'Judge-recoverable (JRC)';

  @override
  String get jrcHint =>
      'Pack with a designated judge’s public key. Any camera sees only a hiding commitment; only the judge can recover the file.';

  @override
  String get judgePublicKey => 'Judge public key';

  @override
  String get judgePublicKeyHint =>
      '64 hex characters of the judge’s X25519 public key.';

  @override
  String get judgePublicKeyInvalid =>
      'The judge public key must be exactly 64 hex characters.';

  @override
  String get generateJudgeKey => 'Generate a judge key';

  @override
  String get generateJudgeKeyHint =>
      'Creates a fresh keypair you can share with a sender.';

  @override
  String get judgeSecretKey => 'Judge secret key';

  @override
  String get judgeSecretKeyHint =>
      '64 hex characters of the judge’s X25519 secret key.';

  @override
  String get judgeSecretKeyInvalid =>
      'The judge secret key must be exactly 64 hex characters.';

  @override
  String get enterJudgeKey => 'This transfer is judge-recoverable';

  @override
  String get enterJudgeKeyBody =>
      'Only the designated judge can recover this file. Enter the matching secret key.';

  @override
  String get wrongJudgeKey => 'Wrong judge key. Try again.';

  @override
  String get judgeKeyCopied => 'Judge key copied.';

  @override
  String get appearance => 'Appearance';

  @override
  String get advanced => 'Advanced';

  @override
  String get restoreDefaults => 'Restore defaults';
}
