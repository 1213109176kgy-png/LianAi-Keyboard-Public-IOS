# 恋爱键盘 iOS

当前功能范围与额外入口清理见 [移除安卓没有的额外功能](docs/移除额外功能对照.md)。最新真机输入修复见 [触摸响应、音频阻塞与候选刷新记录](docs/触摸响应与候选刷新优化.md)，前一轮见 [底部占位与流畅度记录](docs/真机底部占位与输入流畅度修复.md)。
SwiftUI 主 App + UIKit 键盘扩展，按 Android 1.5.9（39）的界面与功能基线移植。使用 Universe Keyboard 的原生 Rime 桥接和固定版本 iOS 引擎制品，支付沿用现有后端的支付宝 WAP 流程。

当前为可编译、可在模拟器运行的首版移植，尚未完成全部真机和线上业务验收。本轮两端逐页对照与修复见 [一致性验收](docs/一致性验收.md)。完整进度、已知差异及待办见 [实施进度与验收](docs/实施进度与验收.md)，产品范围见 [实施计划](实施计划.md) 与 [Android 功能基线](docs/Android功能基线.md)。

## 环境与构建

- Apple Silicon Mac；Xcode 27.0 已验证。
- 最低部署 iOS 18.0；已在 iOS 27.0 模拟器及 iOS 18.7.8 的 iPhone 16 Pro Max 验证键盘输入；完整真机业务验收仍未完成。
- 项目没有 CocoaPods、远端 Swift 包或 Expo 依赖。12 个 Rime XCFramework 通过固定清单恢复，不纳入 Git。
- 当前制品的部分 Boost 模拟器切片仅支持 arm64，因此工程限定 arm64，不支持 Intel 模拟器。

```bash
git clone https://github.com/1213109176kgy-png/LianAi-Keyboard-Public-IOS.git
cd LianAi-Keyboard-Public-IOS
bash scripts/ensure_rime_vendor.sh fetch
python3 scripts/generate_project.py
open LianAiKeyboard.xcodeproj
```

在 Xcode 选择 `LianAiKeyboard` scheme 和 iPhone 模拟器后运行。项目已提交生成器输出，无需每次重新生成；增删 Swift 文件时运行生成器同步文件引用。生成器不需要安装第三方 Python 包。

无签名构建检查：

```bash
xcodebuild -project LianAiKeyboard.xcodeproj -scheme LianAiKeyboard \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build-artifacts/DerivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project LianAiKeyboard.xcodeproj -scheme LianAiKeyboard \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath .build-artifacts/Device CODE_SIGNING_ALLOWED=NO build
```

## 真机签名

复制 `config/Signing.xcconfig.example` 为 `config/Signing.xcconfig`，填入自己的 Apple Developer Team。该文件已忽略，不能提交真实签名资料。

两个 target 必须使用同一 Team，并在开发者后台开通对应标识及共享能力：

| 项目 | 当前标识 |
| --- | --- |
| 主 App | `com.lianai.keyboard.ios` |
| 键盘扩展 | `com.lianai.keyboard.ios.Keyboard` |
| App Group | `group.com.lianai.keyboard` |
| Keychain Access Group | `$(AppIdentifierPrefix)com.lianai.keyboard.shared` |
| URL scheme | `lianai` |

给自己的账号设置独立命名空间，可在源码副本中运行：

```bash
python3 scripts/configure_friend_signing.py --namespace com.yourname.lianaikeyboard
```

将 namespace 换成自己的唯一英文标识。脚本同步修改主 App / 扩展 Bundle ID、App Group、共享 Keychain 模板与客户端组名，并重新生成项目；随后在 Xcode 为两端选择同一 Personal Team。脚本不会登录账号或执行签名。无签名的 `.app` 不能直接安装到真机。

朋友使用 Windows 的自签流程见 [安装说明](docs/朋友Windows安装流程.md)。仓库提交源码及文档；IPA、源码体验 ZIP、签名文件和本地测试产物不纳入 Git。跨账号第三方重签的共享权限仍需在接收者设备验证。

## 启用键盘

1. 在系统「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」添加「恋爱键盘」。
2. 返回输入框，长按系统地球键选择恋爱键盘。九键与 26 键拼音使用内置词典，离线可用。
3. 在线 AI、跨应用粘贴和共享结果写入需要开启「允许完全访问」。首次发送 AI 内容还会单独征求授权。
4. 首次在主 App 开启键盘语音会话并授权，返回聊天后可长按带麦克风图标的空格说话、松开结束识别、上滑取消。识别内容显示在原键盘上方，按键位置保持不变。会话不再因闲置超时关闭；音频中断、App 被结束或重启后需重新开启。

## 业务配置

官方业务地址沿用 `https://lianai.bahuang.tech/api/app`。没有在工程内嵌入后台管理员账号、用户密码或模型密钥。

- 官方文本/截图通道：登录并具备有效 VIP，读取后台功能配置后调用代理。
- 自定义文本/图片：在「我的 → 设置 → 大模型配置」配置服务商、HTTPS 地址、API Key 与模型；未登录也可使用完整的自配模型。登录后会先刷新账号配置，账号错误不会静默绕过。
- 键盘语音：优先沿用已配置 MiMo ASR Key 或官方登录通道，均未配置时使用 Apple Speech（优先设备端，不支持时使用 Apple 在线服务）；需麦克风授权，Apple 路径另需语音识别授权。密钥和 token 存在共享 Keychain，其他设置存 App Group。
- 支付宝：公开读取套餐及支付渠道；登录下单后通过系统浏览器打开后端签发的支付宝 WAP 地址。回到 App 通过服务端查单确认到账，支持待付订单恢复与幂等重试。没有接 StoreKit 或 Apple 自动续订，也没有集成支付宝原生 SDK。
- 后台目前仍使用其既有支付返回页。客户端支持 `lianai://payment-return`，但不把自动回跳作为成功付款的前提，不信任 URL 参数授予会员。

没有执行真实支付、注册测试账号或修改线上后台。真实账户登录、扣费、通知到账、真机 Keychain 共享仍需联调。

## 验证

```bash
swift test --package-path Packages/LianAiCore
swift test --package-path Packages/KeyboardCore
bash scripts/test_ios.sh 017E6ED3-2980-43B9-B1E0-3033D432C0FE
```

最后一条传入本机已启动的 iPhone 模拟器 ID。在 Xcode 27 的 Device Hub「Device → Keyboard」关闭 Simulate Hardware Keyboard，确保显示屏幕键盘。系统键盘启用测试目前按中文系统验证；它会在该模拟器启用恋爱键盘，不操作真实手机。XCTest 覆盖真实 Rime 候选、九键上屏、英文补全、草稿隔离、页面导航与登录校验。业务包额外覆盖支付安全、账号切换、迟到响应、模型路由及 WAV 格式。

测试附件位于 `.build-artifacts/DerivedData/Logs/Test/*.xcresult`。示例图及本次结果见 [验收记录](docs/实施进度与验收.md)。

## 目录

```text
App/                       主 App 页面、录音/选图、词典下载
Keyboard/                  安卓布局的 UIKit 键盘与 AI 面板
SharedUI/                  Rime 会话、拼音读音、英文词典
Packages/LianAiCore/        账号、路由、支付、存储、协议测试
Packages/KeyboardCore/      上游基础模块与测试
Packages/RimeBridge/        上游原生桥接和忽略的 Vendor 制品
Resources/                 内置词典、拼音/英文数据、隐私清单
Licenses/                  随 App 打包的第三方许可文本
Tests/ / UITests/           宿主引擎集成测试、系统扩展交互测试
scripts/ / config/         项目生成、依赖恢复、签名示例、来源锁定
```

本项目整体按 GPL-3.0-or-later 分发，Universe 代码保留 MIT 许可。具体来源及修改说明见 [第三方声明](THIRD_PARTY_NOTICES.md)，数据处理见 [隐私说明](PRIVACY.md)。
