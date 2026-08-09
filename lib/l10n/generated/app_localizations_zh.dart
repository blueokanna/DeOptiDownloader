// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'DeOptiDownloader';

  @override
  String get tagline => '基于喷泉码的二维码光传传输';

  @override
  String get send => '发送';

  @override
  String get receive => '接收';

  @override
  String get sendTitle => '通过光传输文件';

  @override
  String get receiveTitle => '从屏幕接收';

  @override
  String get sendSubtitle => '选择文件或粘贴文本——应用会将其以不断变化的二维码流形式输出。';

  @override
  String get receiveSubtitle => '将摄像头对准发送方的屏幕——应用会从二维码流中还原出文件。';

  @override
  String get privacyNote => '纯光学传输：两台设备之间不存在任何网络路径。未加密时，任何对准屏幕的摄像头都能读取内容。';

  @override
  String get pickFile => '选择文件';

  @override
  String get pasteSnippet => '粘贴文本片段';

  @override
  String get fileTooLarge => '文件超过 64 MB 的光学传输上限。';

  @override
  String get fileName => '文件名';

  @override
  String get fileSize => '大小';

  @override
  String get fileType => '类型';

  @override
  String get snippetHint => '粘贴或输入要发送的文本…';

  @override
  String get snippetEmpty => '请先输入一些文本。';

  @override
  String get encryption => '使用密码加密';

  @override
  String get encryptionHint => '认证加密（XChaCha20-Poly1305）。接收方必须输入相同的密码。';

  @override
  String get password => '密码';

  @override
  String get passwordHint => '接收方解码数据流时需要使用。';

  @override
  String get startStream => '开始传输';

  @override
  String get stop => '停止';

  @override
  String get pause => '暂停';

  @override
  String get resume => '继续';

  @override
  String get settings => '设置';

  @override
  String get framesPerSecond => '帧率';

  @override
  String get frameSize => '帧大小';

  @override
  String get frameSizeHint => '每个二维码帧的总字节数；帧越大传输越快，但二维码也越大。';

  @override
  String get qrSize => '二维码尺寸';

  @override
  String get streaming => '传输中';

  @override
  String get paused => '已暂停';

  @override
  String get waitingForReceiver => '请将接收方摄像头对准本屏幕。';

  @override
  String get framesSent => '已发送帧数';

  @override
  String get session => '会话';

  @override
  String get sourceBlocks => '源块数 (K)';

  @override
  String get blockSize => '块大小';

  @override
  String get qrVersion => '二维码版本';

  @override
  String get elapsed => '已用时间';

  @override
  String get suggestLowerSettings => '如果接收方无法锁定，请降低帧率和帧大小。';

  @override
  String get cameraUnavailable => '当前设备没有可用摄像头。在桌面上你也可以用浏览器进行接收。';

  @override
  String get cameraPermissionDenied => '摄像头权限被拒绝。请在系统设置中开启后再接收。';

  @override
  String get waitingForSender => '请将摄像头对准发送方屏幕…';

  @override
  String get pointCamera => '让二维码保持在画面内。解码出帧后会自动锁定数据流。';

  @override
  String get noSignalTitle => '没反应？';

  @override
  String get noSignalBody => '请确认发送方正在传输。若仍然失败，可将发送方设置为 24 帧/秒、1465 字节帧。';

  @override
  String get progressFrames => '帧';

  @override
  String get receiverLocked => '已锁定数据流';

  @override
  String get transferMode => '模式';

  @override
  String get complete => '传输完成';

  @override
  String get save => '保存';

  @override
  String get share => '分享';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get receiveAgain => '再次接收';

  @override
  String get backHome => '返回首页';

  @override
  String get enterPassword => '此传输已加密';

  @override
  String get wrongPassword => '密码错误，请重试。';

  @override
  String get confirm => '确定';

  @override
  String get cancel => '取消';

  @override
  String get diagnostics => '诊断';

  @override
  String get selfTest => '运行 Rust 自检';

  @override
  String get selfTestPass => '自检通过：打包 → 发送 → 接收 → 解包 全程无误。';

  @override
  String get selfTestFail => '自检失败：';

  @override
  String get about => '关于';

  @override
  String get aboutBody =>
      'Rust 核心（deopti_transfer + rustbinary）负责喷泉码、容器打包、会话清单与二维码编解码；Flutter 负责渲染二维码流并读取摄像头。支持 Android、iOS、HarmonyOS Next、Windows、macOS、Linux、Web/WASM 与 Docker。';

  @override
  String get unsupportedPlatform => '此平台暂不支持摄像头采集。';

  @override
  String get optional => '可选';

  @override
  String get manifestSetup => '设置二维码';

  @override
  String get manifestScanHint => '先扫描此码预览传输内容——数据帧将自动开始。';

  @override
  String get manifestIncoming => '正在接收';

  @override
  String get manifestEncrypted => '已加密';

  @override
  String get streamStarting => '数据流即将开始…';

  @override
  String get theme => '主题';

  @override
  String get themeHint => '基于 Material Design 3 的配色方案与自适应图形。';

  @override
  String get themeMode => '主题模式';

  @override
  String get themeModeSystem => '跟随系统';

  @override
  String get themeModeLight => '浅色';

  @override
  String get themeModeDark => '深色';

  @override
  String get themeIndigoLight => '靛蓝（浅色）';

  @override
  String get themeIndigoDark => '靛蓝（深色）';

  @override
  String get themeAmoled => 'AMOLED 深黑';

  @override
  String get themeAmoledHint => '为 OLED 屏幕提供纯黑界面。';

  @override
  String get themeViolet => '紫罗兰（表现力）';

  @override
  String get themeMidnight => '午夜（保真）';

  @override
  String get themeSunset => '日落（鲜明）';

  @override
  String get themeMonochrome => '单色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get wallpaper => '壁纸';

  @override
  String get wallpaperNone => '无背景';

  @override
  String get wallpaperNoneHint => '纯主题表面，界面后方不显示图片。';

  @override
  String get wallpaperBuiltin => '壁纸';

  @override
  String get wallpaperCustom => '自定义图片';

  @override
  String get wallpaperCustomHint => '从相册中选择照片作为应用背景。';

  @override
  String get wallpaperBlur => '模糊';

  @override
  String get wallpaperBlurHint => '拖动滑块柔化界面背后的背景。';

  @override
  String get wallpaperPick => '选择图片';

  @override
  String get wallpaperRemove => '移除自定义图片';

  @override
  String get jrc => '法官可恢复（JRC）';

  @override
  String get jrcHint => '使用指定法官的公钥打包。任何摄像头只能看到隐藏承诺；只有法官能恢复文件。';

  @override
  String get judgePublicKey => '法官公钥';

  @override
  String get judgePublicKeyHint => '法官 X25519 公钥的 64 位十六进制字符。';

  @override
  String get judgePublicKeyInvalid => '法官公钥必须恰好为 64 位十六进制字符。';

  @override
  String get generateJudgeKey => '生成法官密钥';

  @override
  String get generateJudgeKeyHint => '创建一个全新密钥对，可分享给发送方。';

  @override
  String get judgeSecretKey => '法官私钥';

  @override
  String get judgeSecretKeyHint => '法官 X25519 私钥的 64 位十六进制字符。';

  @override
  String get judgeSecretKeyInvalid => '法官私钥必须恰好为 64 位十六进制字符。';

  @override
  String get enterJudgeKey => '此传输为法官可恢复';

  @override
  String get enterJudgeKeyBody => '只有指定法官能恢复此文件。请输入匹配的私钥。';

  @override
  String get wrongJudgeKey => '法官密钥错误，请重试。';

  @override
  String get judgeKeyCopied => '法官密钥已复制。';

  @override
  String get appearance => '外观';

  @override
  String get advanced => '高级';

  @override
  String get restoreDefaults => '恢复默认';
}
