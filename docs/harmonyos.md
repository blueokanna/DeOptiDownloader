# HarmonyOS Next 集成指南

DeOptiDownloader 的应用层与平台无关：接收端只依赖
`CameraFrameSource`（`lib/src/core/camera/camera_frame_source.dart`）抽象。
接入 HarmonyOS Next 只需要提供一个摄像头后端，然后在该平台的 `camera_source_*`
实现中把它注册到工厂即可。

## 需要什么

1. **HarmonyOS 版 Flutter SDK**（OpenHarmony/ohos 分支）以及 HarmonyOS 的
   Flutter 工程配置（`ohos/` 目录、DevEco Studio 的 signing 配置）。
2. **一个 HarmonyOS 摄像头插件**，能够：
   - 打开后置摄像头并显示预览；
   - 以 YUV420 或 RGBA 形式持续输出帧（用于 Rust 二维码解码）。

社区常用方案：`camera_ohos`（OpenHarmony 社区维护的 `camera` 插件）或其他
`camera` 平台的 HarmonyOS 实现。若所选插件实现了
`camera_platform_interface`，那么现有的 `PluginCameraSource`
（`plugin_camera_source.dart`）可以**直接复用**——只需把它注册到
`camera_source_factory.dart`。

## 接入步骤（约 50 行）

### 1. 实现 `CameraFrameSource`

```dart
// lib/src/core/camera/harmony_camera_source.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_frame_source.dart';
import 'luma_frame.dart';

/// HarmonyOS camera backend.
///
/// Adapt a HarmonyOS camera plugin: open the back camera, start an image
/// stream, forward each YUV420/RGBA frame as a [LumaFrame].
class HarmonyCameraSource implements CameraFrameSource {
  HarmonyCameraSource({this.maxFramesPerSecond = 20});

  final int maxFramesPerSecond;
  final StreamController<LumaFrame> _frames = StreamController<LumaFrame>();

  // TODO: instance of your ohos camera controller
  // final _camera = OhosCameraController(...);

  @override
  String get name => 'harmony-camera';

  @override
  Stream<LumaFrame> get frames => _frames.stream;

  @override
  Future<void> initialize() async {
    // e.g. await _camera.startImageStream(_onImage);
  }

  void _onImage(Uint8List yPlane, int width, int height, {bool rgba = false}) {
    if (rgba) {
      // Canvas/web-style RGBA frame:
      _frames.add(LumaFrame(
        data: yPlane, width: width, height: height, rgba: true,
        timestamp: DateTime.now(),
      ));
    } else {
      // YUV420 Y-plane (tight, row-major) — the common mobile case:
      _frames.add(LumaFrame(
        data: yPlane, width: width, height: height, rgba: false,
        timestamp: DateTime.now(),
      ));
    }
  }

  @override
  Widget buildPreview() {
    // return OhosCameraPreview(...);
    return const SizedBox.shrink();
  }

  @override
  Future<void> dispose() async {
    // await _camera.stopImageStream();
    await _frames.close();
  }
}
```

### 2. 在工厂中按平台注册

```dart
// lib/src/core/camera/camera_source_ohos.dart
import 'camera_frame_source.dart';
import 'harmony_camera_source.dart';

CameraFrameSource createCameraSource() => HarmonyCameraSource();
```

然后在 `camera_source_factory.dart` 的顶层条件导入中增加 ohos 分支：

```dart
import 'camera_source_io.dart'
    if (dart.library.js_interop) 'camera_source_web.dart'
    if (dart.library.ohos) 'camera_source_ohos.dart' as impl;
```

> `dart.library.ohos` 由 HarmonyOS 版 Flutter SDK 提供；若你的 SDK 尚未暴露
> 该库标志，也可以改用 `Platform.operatingSystem == 'ohos'` 在运行时分发。

### 3. 构建

```bash
# 使用 HarmonyOS 版 Flutter SDK
flutter pub get
flutter build hap --release   # 或 ohos 构建命令，取决于 SDK
```

rust_builder 的 cargokit 会自动把 Rust 核心交叉编译到 ohos 目标
（`aarch64-unknown-linux-ohos` / `x86_64-unknown-linux-ohos`，需先安装对应
rustup target）。

## 其余无需改动

- 发送页、接收页、会话逻辑、二维码编解码：全部与平台无关，原样可用。
- 文件选择：`file_picker` 若尚未支持 ohos，可在 `FileService` 增加一个
  HarmonyOS 实现（实现同一接口，用 ohos 的 `filePicker` API）。
- 屏幕常亮：`wakelock_plus` 若未支持 ohos，可换用 ohos 的
  `window.setWindowKeepScreenOn`。
