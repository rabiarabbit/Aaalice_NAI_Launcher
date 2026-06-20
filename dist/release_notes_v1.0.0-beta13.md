## NAI Launcher v1.0.0-beta13 更新日志

本次更新在 `v1.0.0-beta12` 的基础上新增 macOS 最小适配，并开始提供 Windows 与 macOS 双平台发布包。

### 新增

- **macOS 最小适配**：支持启动、登录、本地数据库、在线图库视频、系统代理、Keychain 安全存储、图片复制和文件定位。
- **macOS 应用与构建支持**：新增 macOS runner、应用图标、构建脚本和本地签名辅助脚本，方便 macOS 用户和贡献者自行构建。
- **双平台自动发布**：后续推送 `v*` tag 后，会自动构建 Windows 与 macOS 压缩包并发布到同一个 GitHub Release。

### 改进

- **macOS 标识更正式**：bundle id 已调整为 `com.aaalice.naiLauncher`，避免继续使用 `com.example` 和下划线标识。
- **README 全面刷新**：文档已按当前功能、平台状态、构建步骤和发布流程重新整理。

### 修复

- 修复复制 JPG、JPEG 或 WebP 图片时可能被错误当作 PNG 写入剪贴板的问题；复制前会统一生成可粘贴的 PNG 数据，并继续尊重“复制/拖拽时剥离元数据”的设置。

### 贡献

- 感谢 [@Miint-Sunny](https://github.com/Miint-Sunny) 贡献 macOS 最小适配。

### 下载

- Windows 压缩包：`NAI_Launcher_Windows_1.0.0-beta13+16.zip`
- macOS 压缩包：`NAI_Launcher_macOS_1.0.0-beta13+16.zip`
