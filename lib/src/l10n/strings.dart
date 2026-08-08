import 'package:flutter/widgets.dart';

/// Lightweight two-language localization (zh / en).
///
/// No external i18n dependency: a single `Strings` instance is resolved from
/// the ambient `Locale`, with English as the fallback. Keeping the surface
/// small (one class, two instances) keeps the app decoupled from the
/// localization machinery while staying fully translatable.
class Strings {
  const Strings({
    required this.appName,
    required this.tagline,
    required this.send,
    required this.receive,
    required this.sendTitle,
    required this.receiveTitle,
    required this.sendSubtitle,
    required this.receiveSubtitle,
    required this.privacyNote,
    required this.pickFile,
    required this.pasteSnippet,
    required this.fileTooLarge,
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.snippetHint,
    required this.snippetEmpty,
    required this.encryption,
    required this.encryptionHint,
    required this.password,
    required this.passwordHint,
    required this.startStream,
    required this.stop,
    required this.pause,
    required this.resume,
    required this.settings,
    required this.framesPerSecond,
    required this.frameSize,
    required this.frameSizeHint,
    required this.qrSize,
    required this.streaming,
    required this.paused,
    required this.waitingForReceiver,
    required this.framesSent,
    required this.session,
    required this.sourceBlocks,
    required this.blockSize,
    required this.qrVersion,
    required this.elapsed,
    required this.suggestLowerSettings,
    required this.cameraUnavailable,
    required this.cameraPermissionDenied,
    required this.waitingForSender,
    required this.pointCamera,
    required this.noSignalTitle,
    required this.noSignalBody,
    required this.progressFrames,
    required this.receiverLocked,
    required this.transferMode,
    required this.complete,
    required this.save,
    required this.share,
    required this.copy,
    required this.copied,
    required this.receiveAgain,
    required this.backHome,
    required this.enterPassword,
    required this.wrongPassword,
    required this.confirm,
    required this.cancel,
    required this.diagnostics,
    required this.selfTest,
    required this.selfTestPass,
    required this.selfTestFail,
    required this.about,
    required this.aboutBody,
    required this.unsupportedPlatform,
    required this.optional,
    required this.manifestSetup,
    required this.manifestScanHint,
    required this.manifestIncoming,
    required this.manifestEncrypted,
    required this.streamStarting,
  });

  final String appName;
  final String tagline;
  final String send;
  final String receive;
  final String sendTitle;
  final String receiveTitle;
  final String sendSubtitle;
  final String receiveSubtitle;
  final String privacyNote;
  final String pickFile;
  final String pasteSnippet;
  final String fileTooLarge;
  final String fileName;
  final String fileSize;
  final String fileType;
  final String snippetHint;
  final String snippetEmpty;
  final String encryption;
  final String encryptionHint;
  final String password;
  final String passwordHint;
  final String startStream;
  final String stop;
  final String pause;
  final String resume;
  final String settings;
  final String framesPerSecond;
  final String frameSize;
  final String frameSizeHint;
  final String qrSize;
  final String streaming;
  final String paused;
  final String waitingForReceiver;
  final String framesSent;
  final String session;
  final String sourceBlocks;
  final String blockSize;
  final String qrVersion;
  final String elapsed;
  final String suggestLowerSettings;
  final String cameraUnavailable;
  final String cameraPermissionDenied;
  final String waitingForSender;
  final String pointCamera;
  final String noSignalTitle;
  final String noSignalBody;
  final String progressFrames;
  final String receiverLocked;
  final String transferMode;
  final String complete;
  final String save;
  final String share;
  final String copy;
  final String copied;
  final String receiveAgain;
  final String backHome;
  final String enterPassword;
  final String wrongPassword;
  final String confirm;
  final String cancel;
  final String diagnostics;
  final String selfTest;
  final String selfTestPass;
  final String selfTestFail;
  final String about;
  final String aboutBody;
  final String unsupportedPlatform;
  final String optional;
  final String manifestSetup;
  final String manifestScanHint;
  final String manifestIncoming;
  final String manifestEncrypted;
  final String streamStarting;

  static const Strings en = Strings(
    appName: 'DeOptiDownloader',
    tagline: 'Fountain-coded QR file transfer over light',
    send: 'Send',
    receive: 'Receive',
    sendTitle: 'Send a file over light',
    receiveTitle: 'Receive from a screen',
    sendSubtitle: 'Pick a file or paste text — the app streams it as an endless series of QR codes.',
    receiveSubtitle: 'Point your camera at a sender’s screen — the app reconstructs the file from the QR stream.',
    privacyNote: 'Optical only: no network path is used between the devices. Without a password the stream is readable by any camera pointed at it.',
    pickFile: 'Pick a file',
    pasteSnippet: 'Paste a text snippet',
    fileTooLarge: 'File exceeds the 64 MB optical transfer limit.',
    fileName: 'Name',
    fileSize: 'Size',
    fileType: 'Type',
    snippetHint: 'Paste or type the text you want to send…',
    snippetEmpty: 'Enter some text first.',
    encryption: 'Encrypt with a password',
    encryptionHint: 'Authenticated encryption (XChaCha20-Poly1305). The receiver must enter the same password.',
    password: 'Password',
    passwordHint: 'Required by the receiver to decode the stream.',
    startStream: 'Start streaming',
    stop: 'Stop',
    pause: 'Pause',
    resume: 'Resume',
    settings: 'Settings',
    framesPerSecond: 'Frame rate',
    frameSize: 'Frame size',
    frameSizeHint: 'Total bytes per QR frame; larger frames move more data but need a bigger QR.',
    qrSize: 'QR size',
    streaming: 'Streaming',
    paused: 'Paused',
    waitingForReceiver: 'Hold the receiver’s camera to this screen.',
    framesSent: 'Frames sent',
    session: 'Session',
    sourceBlocks: 'Source blocks (K)',
    blockSize: 'Block size',
    qrVersion: 'QR version',
    elapsed: 'Elapsed',
    suggestLowerSettings: 'If the receiver cannot lock on, lower the frame rate and frame size.',
    cameraUnavailable: 'No camera is available on this device. On desktop you can receive in a browser instead.',
    cameraPermissionDenied: 'Camera permission was denied. Enable it in system settings to receive.',
    waitingForSender: 'Point the camera at the sender’s screen…',
    pointCamera: 'Keep the QR code inside the frame. A stream locks on automatically once frames are decoded.',
    noSignalTitle: 'Nothing happening?',
    noSignalBody: 'Make sure the sender is streaming. If it still fails, try sender settings of 24 fps and 1465-byte frames.',
    progressFrames: 'Frames',
    receiverLocked: 'Locked to stream',
    transferMode: 'Mode',
    complete: 'Transfer complete',
    save: 'Save',
    share: 'Share',
    copy: 'Copy',
    copied: 'Copied',
    receiveAgain: 'Receive again',
    backHome: 'Back to home',
    enterPassword: 'This transfer is encrypted',
    wrongPassword: 'Wrong password. Try again.',
    confirm: 'OK',
    cancel: 'Cancel',
    diagnostics: 'Diagnostics',
    selfTest: 'Run Rust self-test',
    selfTestPass: 'Self-test passed: pack → send → receive → unpack round trip OK.',
    selfTestFail: 'Self-test failed:',
    about: 'About',
    aboutBody: 'Rust core (deopti_transfer + rustbinary) does the fountain coding, container packing, session manifest and QR codec; Flutter renders the QR stream and reads the camera. Works on Android, iOS, HarmonyOS Next, Windows, macOS, Linux, Web/WASM and Docker.',
    unsupportedPlatform: 'This platform is not supported for camera capture yet.',
    optional: 'Optional',
    manifestSetup: 'Setup QR',
    manifestScanHint: 'Scan this first to preview the transfer — data frames follow automatically.',
    manifestIncoming: 'Incoming',
    manifestEncrypted: 'Encrypted',
    streamStarting: 'Streaming starts in a moment…',
  );

  static const Strings zh = Strings(
    appName: 'DeOptiDownloader',
    tagline: '基于喷泉码的二维码光传传输',
    send: '发送',
    receive: '接收',
    sendTitle: '通过光传输文件',
    receiveTitle: '从屏幕接收',
    sendSubtitle: '选择文件或粘贴文本——应用会将其以不断变化的二维码流形式输出。',
    receiveSubtitle: '将摄像头对准发送方的屏幕——应用会从二维码流中还原出文件。',
    privacyNote: '纯光学传输：两台设备之间不存在任何网络路径。未加密时，任何对准屏幕的摄像头都能读取内容。',
    pickFile: '选择文件',
    pasteSnippet: '粘贴文本片段',
    fileTooLarge: '文件超过 64 MB 的光学传输上限。',
    fileName: '文件名',
    fileSize: '大小',
    fileType: '类型',
    snippetHint: '粘贴或输入要发送的文本…',
    snippetEmpty: '请先输入一些文本。',
    encryption: '使用密码加密',
    encryptionHint: '认证加密（XChaCha20-Poly1305）。接收方必须输入相同的密码。',
    password: '密码',
    passwordHint: '接收方解码数据流时需要使用。',
    startStream: '开始传输',
    stop: '停止',
    pause: '暂停',
    resume: '继续',
    settings: '设置',
    framesPerSecond: '帧率',
    frameSize: '帧大小',
    frameSizeHint: '每个二维码帧的总字节数；帧越大传输越快，但二维码也越大。',
    qrSize: '二维码尺寸',
    streaming: '传输中',
    paused: '已暂停',
    waitingForReceiver: '请将接收方摄像头对准本屏幕。',
    framesSent: '已发送帧数',
    session: '会话',
    sourceBlocks: '源块数 (K)',
    blockSize: '块大小',
    qrVersion: '二维码版本',
    elapsed: '已用时间',
    suggestLowerSettings: '如果接收方无法锁定，请降低帧率和帧大小。',
    cameraUnavailable: '当前设备没有可用摄像头。在桌面上你也可以用浏览器进行接收。',
    cameraPermissionDenied: '摄像头权限被拒绝。请在系统设置中开启后再接收。',
    waitingForSender: '请将摄像头对准发送方屏幕…',
    pointCamera: '让二维码保持在画面内。解码出帧后会自动锁定数据流。',
    noSignalTitle: '没反应？',
    noSignalBody: '请确认发送方正在传输。若仍然失败，可将发送方设置为 24 帧/秒、1465 字节帧。',
    progressFrames: '帧',
    receiverLocked: '已锁定数据流',
    transferMode: '模式',
    complete: '传输完成',
    save: '保存',
    share: '分享',
    copy: '复制',
    copied: '已复制',
    receiveAgain: '再次接收',
    backHome: '返回首页',
    enterPassword: '此传输已加密',
    wrongPassword: '密码错误，请重试。',
    confirm: '确定',
    cancel: '取消',
    diagnostics: '诊断',
    selfTest: '运行 Rust 自检',
    selfTestPass: '自检通过：打包 → 发送 → 接收 → 解包 全程无误。',
    selfTestFail: '自检失败：',
    about: '关于',
    aboutBody: 'Rust 核心（deopti_transfer + rustbinary）负责喷泉码、容器打包、会话清单与二维码编解码；Flutter 负责渲染二维码流并读取摄像头。支持 Android、iOS、HarmonyOS Next、Windows、macOS、Linux、Web/WASM 与 Docker。',
    unsupportedPlatform: '此平台暂不支持摄像头采集。',
    optional: '可选',
    manifestSetup: '设置二维码',
    manifestScanHint: '先扫描此码预览传输内容——数据帧将自动开始。',
    manifestIncoming: '正在接收',
    manifestEncrypted: '已加密',
    streamStarting: '数据流即将开始…',
  );

  /// Resolves the strings for the ambient [context] locale (en fallback).
  static Strings of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode;
    return code == 'zh' ? zh : en;
  }
}
