# Android 壳（占位）

按 Roadmap 后续迭代，技术选型已定（与 iOS 壳同构）：

- Kotlin + WebView：加载桌面端 `/m` 手机页，壳不做对话 UI
- 扫码：CameraX + ML Kit Barcode Scanning
- 凭证：EncryptedSharedPreferences / Keystore，按 `host:port` 隔离
- 深链：`astra://bind?url=...`
- WebView 导航白名单：仅允许绑定桌面的 `host:port`

实现时请对照 [docs/BINDING_PROTOCOL.md](../docs/BINDING_PROTOCOL.md)，
壳的职责与安全义务与 iOS 侧一致。
