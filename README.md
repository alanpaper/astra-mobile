# Astra Mobile

Astra 桌面端的手机客户端（开源）。扫描桌面端生成的二维码完成绑定，在手机上查看并参与 Astra 的 Agent 对话。

壳的理念：**薄**。扫码、保管设备密钥、全屏 WebView —— 对话界面由桌面端内置的手机页（`/m`）提供，随桌面端版本自动升级，客户端与桌面端之间不存在需要同步的 UI 副本。

## 功能

- 扫码绑定 / 粘贴链接绑定 / `astra://bind?url=...` 深链
- 多台桌面端凭证管理（iOS Keychain 按 `host:port` 隔离存储，可随时删除）
- WebView 仅允许访问已绑定的桌面端，其余链接交给系统浏览器
- 支持局域网直连与服务器中继两种模式（绑定载荷格式相同）

## 构建（iOS）

要求：Xcode 15+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
brew install xcodegen
cd ios
xcodegen generate
open AstraMobile.xcodeproj
```

在 Xcode 中：Signing & Capabilities 选择你的 Team（免费 Apple ID 亦可真机调试，签名 7 天有效；付费开发者账号可 TestFlight 分发），选模拟器或真机 Cmd+R。

模拟器没有摄像头，可用「粘贴链接绑定」或深链方式测试。

## 协议

壳与桌面端「手机遥控桥」的契约见 [docs/BINDING_PROTOCOL.md](docs/BINDING_PROTOCOL.md)。

## Roadmap

- [x] R4.1 iOS 壳（SwiftUI + AVFoundation 扫码 + Keychain）
- [ ] R4.2 深链完善 + 多桌面凭证管理增强
- [ ] Android 壳（Kotlin + CameraX/ML Kit + Keystore）—— 目录已占位，选型见 [android/README.md](android/README.md)

## License

[MIT](LICENSE)
