# 恋爱键盘 Windows 体验安装步骤

2026-11-04 最新修复版，1.5.9（39），要求 iPhone iOS 18.0 及以上。

**先说明：这是待自签 IPA，需要电脑签名；不是微信里点开就能安装的包。本机已真机测试，但朋友账号通过 Sideloadly 重签后的键盘共享权限尚未验证。**

## 需要准备

- 一台 Windows 电脑、iPhone 和数据线。
- 朋友自己的 Apple 账号及验证码。
- 本文件旁的 `LianAiKeyboard-1.5.9-39-20261104-input-fix-unsigned.ipa`。

## 安装

1. 电脑打开 [Sideloadly 官方网站](https://sideloadly.io/)，下载 Windows 版本。按官网提示安装所需的 Apple 桌面版 iTunes / iCloud 依赖。
2. 用数据线连接自己的 iPhone，解锁，并在手机点击“信任这台电脑”。
3. 打开 Sideloadly，选择已连接的 iPhone，把 IPA 文件拖进去。
4. 输入朋友自己的 Apple 账号，点击 Start；密码、验证码按工具提示在朋友自己的电脑输入，不用发给开发者。
5. **保留键盘扩展，不要开启 Remove Extensions / 删除扩展。** 如果提示只能删扩展才能安装，先不要继续：删掉就没有恋爱键盘了。
6. 安装完成后，如系统提示不信任开发者：设置 → 通用 → VPN 与设备管理 → 开发者 App → 找到自己的账号 → 信任。
7. 如提示需要开发者模式：设置 → 隐私与安全性 → 开发者模式，按提示开启、重启并确认。
8. 打开恋爱键盘 App。再到设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 恋爱键盘，点击它开启“允许完全访问”。
9. 在备忘录、微信或 App 的键盘试用页，长按系统地球键，选择恋爱键盘。

## 测试

- 连续打字、选候选、滑动候选、删除和英文空格上屏。删空拼音后重新输入，不应残留额外字母。
- AI 功能：在主 App 配好可用的 AI 服务或实际有权限的账号，再测“帮你回 / 超会说”。安装包没有私人 API Key 或假测试回复。
- 语音：先在主 App 开启键盘语音会话，回到聊天长按空格，松开结束，上滑取消。

## 重要：键盘重签失败时

如果工具报 App Group / Keychain / Bundle ID 权限错误，或只装得上主 App、设置却不能同步到键盘，请把**报错截图或工具日志**发给开发者。

本应用主 App 与键盘扩展有共享权限要求，通用重签工具是否能自动正确处理它们仍待朋友设备验证。不要靠删除扩展或只改一个 Bundle ID 来绕过。完整配置办法见同目录“安装说明.md”的 Mac + Xcode 路线；只有 Windows 时，该备用路线需要借用 Mac，不能宣称这个 IPA 已保证随便重签即可完整使用。

## 七天后

免费账号签名七天到期后，用相同 Apple 账号和相同 Bundle ID 重新覆盖安装。可以在 Sideloadly 开启自动刷新；电脑需能通过 USB 或同一局域网连接手机，不能保证电脑离线时仍自动续签。

文件 SHA-256 可对照 `SHA256SUMS.txt`，可在 PowerShell 执行：

```powershell
Get-FileHash .\LianAiKeyboard-1.5.9-39-20261104-input-fix-unsigned.ipa -Algorithm SHA256
```

参考：[Apple 免费 Personal Team 限制](https://developer.apple.com/help/account/basics/about-your-developer-account/)、[Sideloadly 官方 FAQ](https://sideloadly.io/faq.html)。
