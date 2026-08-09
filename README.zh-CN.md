# DeOptiDownloader

**基于喷泉码的二维码光传传输 —— Rust 核心 + Flutter 跨端应用。**

只需**一块屏幕和一枚摄像头**，就能在两台设备之间传输文件：发送方将文件渲染成
不断变化的二维码流，接收方用摄像头对准屏幕即可还原出完整文件。**设备之间不存
在任何网络路径，无需配对，除摄像头外无需任何权限。** 数据以光为媒介传输。

English version: [README.md](README.md)。

---

## 核心特性

- **喷泉码（LT 码）** —— 发送方从不重复同一帧：每一帧二维码都是源块的
  全新编码组合。接收方只需按任意顺序收集约 K·1.15 个不重复帧即可完整解码。
  **丢帧只浪费时间，绝不破坏正确性。**
- **自描述帧结构** —— 25 字节帧头携带会话 ID、序号、块数/块大小、总长度与
  BLAKE3 完整性标签。无需握手：接收方可在流传输中途锁定，发送方重启后自动
  重新锁定。
- **DCF3 容器** —— 保留文件名、媒体类型；仅在有益时启用 gzip；携带原始字节的
  BLAKE3 摘要；在给出文件前完成全部校验。
- **会话清单（基于 `rustbinary`）** —— 数据流开始前，发送方先展示一个承载文件名、
  大小、块布局与会话 ID 的小型设置二维码。接收方扫描后即可在首个数据帧到达前
  **预览传输内容**，并校验随后锁定的数据流确属同一会话。紧凑有界的负载由
  `rustbinary` 二进制编解码器编码（见 `rust/src/api/manifest.rs`）。
- **为流式传输调优的二维码层** —— 纠错级别 L、最小适配版本、Rust 内先降采样
  再解码，保证快速稳定的摄像头解码。
- **可选端到端加密（deopti_transfer 0.1.2）** —— XChaCha20-Poly1305 + 口令
  派生密钥；**以及法官可恢复传输（JRC）**：发送方针对指定法官的公钥提交承诺，
  任何摄像头只能看到隐藏承诺与密文，只有持有匹配私钥的法官才能恢复文件。两者
  均为可选，并在所有原生构建中由 `encryption` Cargo 特性启用。
- **Material 3 设计系统** —— Google 字体（Noto Sans SC，随包内置、全平台离线可
  用）；精选主题注册表（靛蓝浅色/深色、**AMOLED 深黑**——为 OLED 屏幕提供纯黑
  表面、紫罗兰 *表现力*、午夜 *保真*、日落 *鲜明*、单色），每个主题均由
  `ColorScheme.fromSeed` + Material 3 `DynamicSchemeVariant`（色彩风格）与 M3
  形状/动效令牌构建。
- **壁纸与模糊** —— 应用内背景可关闭、可选用随包内置的渐变壁纸，也可从相册
  选择自定义照片，并带有可拖动的**高斯模糊滑杆（0–24 σ）**，在界面后方柔化
  背景。
- **i18n（ARB → gen-l10n）** —— 官方 Flutter 本地化流程：`en` + `zh` ARB 源
  文件、运行时语言切换（跟随系统/English/中文），并通过
  `flutter_localizations` 让 Material 组件完全本地化。
- **预测性返回** —— 已设置 `android:enableOnBackInvokedCallback="true"`，
  Android 13+ 将渲染系统预测性返回手势动画。
- **全平台可用** —— Android、iOS、HarmonyOS Next、Windows、macOS、Linux、
  Web/WASM 与 Docker（容器化 Web 部署）。
- **开箱即用的 CI** —— GitHub Actions 在每次推送时运行 Rust 检查/测试、Flutter
  分析/测试、真实的 Web/WASM 构建与 Docker 构建（见 [.github/workflows](.github/workflows)）。

## 与参考项目功能对齐

参考项目 [bashalarmistalt/decimen-optical-transfer](https://github.com/bashalarmistalt/decimen-optical-transfer) 的全部功能均已
实现并有所扩展：

| 参考项目能力                   | DeOptiDownloader                             |
| ------------------------------ | -------------------------------------------- |
| 发送文件（≤ 64 MB）            | ✅ `file_picker`，64 MB 上限                 |
| 发送文本片段                   | ✅ 片段对话框 → `text/plain` 容器            |
| 喷泉码二维码流                 | ✅ Rust `deopti_transfer` + `qrcode`         |
| 摄像头 → 二维码解码 → 文件     | ✅ Rust `rxing` 解码（原生 + WASM）          |
| 提供文件前校验 SHA-256         | ✅ 容器层完成 BLAKE3 摘要校验                |
| 仅在有益时 gzip                | ✅ 由 `deopti_transfer::pack_file` 处理      |
| 保留文件名 / 媒体类型          | ✅ DCF3 容器                                 |
| 进度与“无信号”提示             | ✅ 进度条、流锁定行、提示卡片                |
| 传输时保持屏幕常亮             | ✅ `wakelock_plus`（发送与接收）             |
| 发送端可调帧率 / 帧大小        | ✅ 10/15/20/24/30/60 fps，500–2953 字节帧    |
| **新增：** 密码加密            | ✅ XChaCha20-Poly1305 + Argon2id（可选）     |
| **新增：** 法官可恢复 JRC      | ✅ deopti_transfer 0.1.2 `pack_file_jrc`     |
| **新增：** 自动重新锁定        | ✅ Rust 内流冲突自动重置                     |
| **新增：** 会话清单二维码      | ✅ `rustbinary` 编码的设置码 + 接收预览      |
| **新增：** 诊断自检            | ✅ `runSelfTest()` + `jrcSelfTest()`         |
| **新增：** Material 3 + 响应式 | ✅ Google 字体、M3 令牌、自适应布局          |
| **新增：** 主题 + 壁纸         | ✅ AMOLED 深黑等 + 模糊 + 自定义照片         |
| **新增：** i18n                | ✅ 官方 ARB/gen-l10n（中/英）                |

## 架构

```
┌────────────────────────── Flutter UI ──────────────────────────┐
│  首页 · 发送 · 接收    （Material 3，中/英双语）               │
│  SenderController / ReceiverController（帧循环、统计）        │
│  CameraFrameSource 抽象（插件 / getUserMedia）                 │
│  QrDisplay（RLE 绘制，60 fps）· FileService（io/web）          │
└──────────────┬───────────────────────────────┬─────────────────┘
               │ flutter_rust_bridge（FRB 2.12） │
┌──────────────▼───────────────────────────────▼─────────────────┐
│  Rust 核心（rust/src/api）                                      │
│  transfer.rs —— 会话、打包/解包、清单二维码、自检               │
│  manifest.rs —— rustbinary 会话清单编解码                       │
│  qr.rs       —— 二维码编码（qrcode）+ 解码（rxing）+ 降采样     │
│  types.rs    —— 跨边界 DTO                                      │
└──────────────┬───────────────────────────────┬─────────────────┘
               │                               │
      deopti_transfer                rustbinary（会话清单
      （LT 喷泉码核心、DCF3         二进制编解码）+ qrcode + rxing
       容器、加密）
```

Rust crate 名为 `rust_lib_scan_downloader`；桥接胶水代码位于
`lib/src/rust/`（自动生成）。所有协议逻辑都在 `deopti_transfer` 中；
`rustbinary` 被真实用于编码紧凑、有界的会话清单负载（见
`rust/src/api/manifest.rs`）；应用层只负责适配桥接。

## 外观：主题、壁纸与 i18n

**主题**（`lib/src/app/theme/app_themes.dart`）。一套精选的 Material 3 主题
注册表，每个主题均由 `ColorScheme.fromSeed` + `DynamicSchemeVariant`（M3 色彩
风格）与共享的形状/动效令牌构建：

| 主题          | 种子色      | 色彩风格（variant）   | 说明                          |
| ------------- | ----------- | --------------------- | ----------------------------- |
| 靛蓝浅色      | `#3D5AFE`   | `tonalSpot`           | 默认                          |
| 靛蓝深色      | `#3D5AFE`   | `tonalSpot`           | 默认深色                      |
| AMOLED 深黑   | `#9FA8FF`   | `tonalSpot`           | 纯黑表面（OLED）              |
| 紫罗兰        | `#7C4DFF`   | `expressive`          | 浅色                          |
| 午夜          | `#3949AB`   | `fidelity`            | 深色                          |
| 日落          | `#FF6E40`   | `vibrant`             | 深色                          |
| 单色          | `#9E9E9E`   | `monochrome`          | 浅色                          |

设置页（首页 → 齿轮图标）可切换主题、主题模式（跟随系统/浅色/深色）与语言。
设置通过 `shared_preferences` 持久化（`lib/src/app/settings_controller.dart`）。

**壁纸**（`lib/src/app/theme/wallpaper.dart`）。三种模式：*无背景*（不显示图片，
也无需模糊调节）、*内置壁纸*（`assets/images/wallpapers/` 中的五张渐变壁纸）、
*自定义*（从相册选择照片，原生端存入应用支持目录 / Web 端存为 data URI）。
启用壁纸后可拖动**高斯模糊滑杆（0–24 σ）**，通过 `ImageFilter.blur` 在整个应用
后方渲染；界面表面会自动变为半透明，让背景透出，同时 on-* 前景色保持可读。

**i18n**（`lib/l10n/*.arb`，由 `flutter gen-l10n` 生成）。官方 ARB →
`AppLocalizations` 流程，配合 `flutter_localizations`；`en` + `zh` 源文件，
支持跟随系统 / English / 中文 运行时切换。

## 法官可恢复传输（JRC）

`deopti_transfer` 0.1.2 新增 JRC 原语：发送方针对**指定法官的公钥**提交文件
承诺；任何截获二维码流的摄像头只能看到隐藏承诺与密文；只有持有匹配**私钥**的
法官才能恢复原始文件。

- **发送方**：在发送页启用 *法官可恢复（JRC）*，粘贴法官公钥（64 位十六进制），
  或用骰子按钮生成全新法官密钥对。打包后的 `envelope` 原样经过喷泉码流传输。
- **法官/接收方**：在接收页，当 JRC 信封到达时应用会请求法官私钥——可直接输入，
  或使用设置页保存的密钥。`unpack_file_jrc_ffi` 在给出文件前会校验绑定关系与
  DCF3 摘要，因此错误密钥会被拒绝。
- 端到端流程由 `jrcSelfTest()`（Rust）与 Flutter 测试套件覆盖；`encryption`
  Cargo 特性通过 `rust/cargokit.yaml` 在所有原生构建中启用（Web 构建保持关闭，
  因为 `wasm32-unknown-unknown` 上 `getrandom` 没有系统随机源）。

## 预测性返回

`AndroidManifest.xml` 已声明 `android:enableOnBackInvokedCallback="true"`，
在 Android 13+ 上系统会为 Flutter 导航器播放预测性返回手势动画（目标 SDK 34+）。

## 平台支持

| 平台           | 发送 | 接收 | 说明                                        |
| -------------- | :--: | :--: | ------------------------------------------- |
| Android        |  ✅  |  ✅  | `camera`（CameraX）YUV420 图像流            |
| iOS            |  ✅  |  ✅  | `camera`（AVFoundation）YUV420 图像流       |
| HarmonyOS Next |  ✅  |  ✅  | 原生 `HarmonyCameraSource`（YUV420 + BGRA） |
| Windows        |  ✅  |  ✅  | `camera_windows` 后端                       |
| macOS          |  ✅  |  ✅  | `camera`（AVFoundation）                    |
| Linux          |  ✅  | ⚠️²  | 尚无统一摄像头后端                          |
| Web / WASM     |  ✅  |  ✅  | getUserMedia + canvas → Rust WASM 解码      |
| Docker         |  ✅  |  ✅  | Rust `deopti-server` 提供 Web 构建          |

² Linux 接收页会给出明确提示，建议使用浏览器版本（Docker 容器或任意浏览器）。

## 快速开始

```bash
# 1. 安装 Rust 桥接工具
cargo install flutter_rust_bridge_codegen --locked --version 2.12.0

# 2. 修改 rust/src/api/* 后重新生成桥接
flutter_rust_bridge_codegen generate

# 3. 在设备 / 桌面运行
flutter pub get
flutter run            # 选择连接的设备
```

### Android 构建要求

Android 构建固定为 **AGP 8.13 + Gradle 8.14.3**（见 `android/settings.gradle.kts`
与 `android/gradle/wrapper/gradle-wrapper.properties`）。AGP 9 的内置 Kotlin 与当前
插件组合不兼容——`file_picker` 11.x 在 AGP 9 下会条件性跳过 Kotlin Gradle 插件（依赖
内置 Kotlin），而 `camera_android_camerax`、`share_plus`、`wakelock_plus`、
`package_info_plus` 仍强制使用经典 KGP——因此项目保持在 AGP 8.x，使所有插件都能
通过经典 KGP 编译。`android/gradle.properties` 还设置了 `kotlin.incremental=false`
以避免 Windows 上已知的 Kotlin 增量缓存故障；`rust_builder/cargokit/gradle/plugin.gradle`
已改用 Gradle 的 `ExecOperations`（Gradle 9 移除了 `Project.exec(Closure)`）。
应用 ID 为 `com.deopti.downloader`。

## Web / WASM

```powershell
# 一次性工具链安装
rustup toolchain install nightly --target wasm32-unknown-unknown --component rust-src
cargo install wasm-pack --locked
cargo install wasm-bindgen-cli --locked --version 0.2.92   # 必须与 rust/Cargo.lock 一致

# 构建
powershell -File scripts/build-web.ps1 -Release

# 用仓库自带的 Rust 服务器托管（纯 std，无 nginx）
cargo build --release --manifest-path rust/server/Cargo.toml
./rust/target/release/deopti-server --root build/web --port 8080
# 打开 http://localhost:8080
```

Rust 核心编译为 `wasm32-unknown-unknown` 并在浏览器中加载（Flutter JavaScript
UI + Rust WASM）。FRB 桥接以**同步**模式生成（`flutter_rust_bridge.yaml` 中的
`default_dart_async: false`），因此应用无需 SharedArrayBuffer 或 worker 线程池，
可运行在任何静态托管上（包括 GitHub Pages）。

Rust `deopti-server`（见下一节）发送 `Cross-Origin-Opener-Policy: same-origin`
与 `Cross-Origin-Embedder-Policy: require-corp`，以便未来重新启用线程化 WASM
构建时继续可用、并保留 SharedArrayBuffer 能力。由于当前同步桥接不要求跨域隔离，
GitHub Pages（`deploy-pages.yml` 工作流）同样可用。

> 注意：应用**不**使用 Flutter 实验性的 `--wasm` 渲染器——该模式与 `dart:html`
> 摄像头/文件后端及 FRB 运行时不兼容。生产 Web 构建为 dart2js + Rust WASM，完全
> 受支持。

## 用 Rust 托管 Web 构建（无 nginx）

部署由仓库自带的**纯 Rust** 静态服务器（`rust/server`，零第三方依赖、仅 std）
托管：

```bash
cargo build --release --manifest-path rust/server/Cargo.toml
./rust/target/release/deopti-server --root build/web --port 8080
```

服务器提供 COOP/COEP 隔离响应头、内容哈希资产的不可变缓存、ETag/304 重新验证、
SPA 回退与严格的路径穿越防护。参数：`--root`、`--host`、`--port`（或
`DEOPTI_ROOT` / `DEOPTI_HOST` / `DEOPTI_PORT` 环境变量）。

## GitHub Actions

仓库内置两个工作流（[.github/workflows](.github/workflows)）：

| 工作流             | 运行内容                                                                                                                                                                                 |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci.yml`           | Rust workspace `fmt --check` + `clippy -D warnings` + `test`（库 + 服务器）；Flutter `analyze` + `test`（先构建原生库）；真实的 `flutter_rust_bridge build-web` + `flutter build web`（上传产物）；`docker build` |
| `deploy-pages.yml` | 构建 Web/WASM 产物并发布到 GitHub Pages（需在 _Settings → Pages → Source: GitHub Actions_ 开启）                                                                                         |

工作流中的每一条命令都与开发者本地执行的命令完全一致，因此绿色流水线是有意义的。

## Docker

```bash
docker build -t deopti-downloader .
docker run --rm -p 8080:8080 deopti-downloader
# 打开 http://localhost:8080
```

`Dockerfile` 为多阶段构建：构建 Flutter Web 产物 + Rust WASM，编译纯 std 的
`deopti-server`，然后由它托管产物——无 nginx、无第三方服务。

## 加密（可选）

未加密时，任何对准屏幕的摄像头都能读取传输内容。若需保密，可在原生目标上启用
Cargo 特性：

```bash
# 原生构建（Android/iOS/桌面）
flutter_rust_bridge build --features encryption   # 按目标平台，或
# 带加密的 Web 构建
dart run flutter_rust_bridge build-web --release --dart-root . --cargo-build-args "--features encryption"
```

发送方设置口令，接收方在容器到达后输入口令。口令永不传输；链路上只有
XChaCha20-Poly1305 密文（Argon2id 密钥派生）。Web/WASM 默认关闭加密，因为
`getrandom` 在默认 wasm 目标上不可用——UI 会在构建不支持时自动隐藏口令选项
（通过 `encryptionSupported()` 检测）。

## 测试

```bash
cargo test --manifest-path rust/Cargo.toml   # 二维码编解码 + 会话清单 + 喷泉码自检
flutter test                                  # 宿主桥接 + 组件测试（含清单往返）
flutter test integration_test -d <device>     # 设备端 E2E（自检、二维码往返、启动）
```

## 目录结构

```
rust/
  Cargo.toml            # workspace：FRB 库 + `server/` 成员
  src/api/transfer.rs   # FRB：会话、打包/解包、清单二维码、自检
  src/api/manifest.rs   # rustbinary 会话清单编解码（有界、带版本）
  src/api/qr.rs         # FRB：二维码编解码、版本表、降采样
  src/api/types.rs      # 共享 DTO
  server/               # deopti-server：纯 std 静态服务器（无 nginx）
lib/
  main.dart             # 启动引导（Rust 初始化非阻塞、错误可见）
  src/app/              # MaterialApp + 设置控制器 + 壁纸作用域
  src/app/theme/        # app_themes（M3 注册表）、壁纸与持久化
  src/app/widgets/      # ModeCard 等共享 M3 组件
  src/l10n/             # ARB 源文件 + 生成的 AppLocalizations（gen-l10n）
  src/core/transfer/    # SenderController、ReceiverController、payload
  src/core/camera/      # CameraFrameSource + 插件 / HarmonyOS / Web 后端
  src/core/qr/          # QrPainter / QrDisplay
  src/core/services/    # FileService（io / web）、judge_keys 辅助
  src/core/util/        # formatBytes、尽力而为的 ScreenKeep
  src/pages/            # 首页、发送、接收、设置（响应式、带动画）
  src/rust/             # 生成的 FRB 胶水代码（请勿手改）
.github/workflows/      # ci.yml + deploy-pages.yml
Dockerfile · scripts/build-web.ps1
```

## 隐私

传输**仅依赖光学**——设备之间不存在任何网络路径。未加密时，发送屏幕上的内容
可被任何对准它的摄像头读取（这正是设计初衷：无网络单向传输，而非**保密**）。需要保密
时请启用加密。

## 许可证

Apache-2.0。核心协议与容器格式来自
[`deopti_transfer`](https://crates.io/crates/deopti_transfer) crate
（Apache-2.0）；`qrcode`、`rxing` 与 `rustbinary` 按其各自作者的说明采用
Apache-2.0 / MIT。
