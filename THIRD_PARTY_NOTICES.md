# 第三方来源与修改说明

本次移植日期：2026-11-03。精确提交、制品摘要及主要数据文件哈希保存在 [来源锁定清单](config/source-provenance.json)。本文件说明实际导入范围，不代表导入了上游完整产品、全部词典或 Android JNI。

| 来源 | 实际导入/用途 | 许可与文本 |
| --- | --- | --- |
| 本地 LianAi-Keyboard `212529fba1e2c4f49cb982564f6bd6ee870ab01a` | Android 产品界面与提示词的 Swift 移植、品牌图片、Lucide 图形、词库/字音/英文数据 | GPL-3.0-or-later；保留根目录 LICENSE、NOTICE，数据各自许可另列 |
| [Universe Keyboard](https://github.com/shchnk1103/Universe-Keyboard/tree/145d24161146b9d38be829a1ebe0a9acf9a7b1d7) | `Packages/KeyboardCore`、`Packages/RimeBridge` 的源代码和测试、固定制品清单、恢复脚本 | MIT，`Licenses/Universe-Keyboard-MIT.txt` |
| [librime](https://github.com/rime/librime) 与上游固定 iOS 制品 | 唯一原生拼音引擎及 ObjC++ 桥接 | BSD-3-Clause，`Licenses/RIME-LIBRIME-BSD-3-Clause.txt` |
| [Rime-Ice](https://github.com/iDvel/rime-ice) | Android 增强包的预编译拼音/T9、英文混输、Emoji 数据及英文单词表 | GPL-3.0，保留 Rime-Ice 许可原文；数据也包含其上游来源标注 |
| [pinyin-data](https://github.com/mozillazg/pinyin-data) 0.15.0 | 汉字多音读音、九键拼音筛选 | MIT，`Licenses/Pinyin-Data-MIT.txt` |
| [Lucide](https://github.com/lucide-icons/lucide) | 将 Android VectorDrawable 路径转换为 SVG，保留线条；不透明 ARGB 转为 iOS 兼容的六位 SVG RGB | ISC，`Licenses/Lucide-ISC.txt` |
| [librime-lua](https://github.com/hchunhui/librime-lua)、Lua | 固定制品的 Lua 插件及运行时；不是新增长期后台脚本能力 | BSD-3-Clause、MIT；许可位于 Licenses |
| [librime-octagram](https://github.com/lotem/librime-octagram/tree/bfb168ca33d8b372596fdf2007933f3da1cf360e) | 固定制品内 grammar 插件 | 根许可 BSD-3-Clause；保留上游关于残留旧 GPL 文件头的来源审计说明 `RIME-OCTAGRAM-PROVENANCE.txt` 与 `Vendor-Octagram-Notice.txt` |
| Boost、glog、LevelDB、MARISA、OpenCC、yaml-cpp | Rime 固定 XCFramework 依赖 | BSL-1.0、BSD、Apache-2.0、MIT 等；逐项原文在 Licenses |
| rime-luna-pinyin 等上游基础数据 | KeyboardCore 中生成的拼音音节目录等上游衍生代码/模板 | 上游 LGPL-3.0 文本、作者及数据来源声明随 Licenses 保留；不表示打包了上游全部方案词典 |
| [RIME-LMDG / Wanxiang](https://github.com/amzxyz/RIME-LMDG) | 用户主动下载的可选 `wanxiang-lts-zh-hans.gram`，默认不打包 | CC-BY-4.0，`Licenses/RIME-WANXIANG-CC-BY-4.0.txt`；沿用 Android 固定大小和 SHA-256 校验 |

## 与 Universe 基线的区别

1. 上游两个包的实现源文件保持原样；`RimeBridge/Package.swift` 增加 `RimeNative` library product，暴露既有 `RimeBridgeObjC` target。
2. 新建恋爱键盘的 App、键盘 UI、共享业务包、Xcode 工程及测试。没有沿用 Universe 的产品首页和设置页面，也未导入其组织流程文件。
3. 原生桥接调用统一收口于 `SharedUI/RimeRuntime.swift`，位于主线程。使用恋爱键盘现有预编译 schema 和词典，在扩展私有目录保存学习数据，按键时不编译词库。
4. 固定制品来自 [上游 Release](https://github.com/shchnk1103/Universe-Keyboard/releases/tag/rime-vendor-ios-1.16.1-lua.1-octagram.1)，按 `config/rime-vendor-manifest.env` 校验。源码/构建方法参见该固定提交的 `docs/architecture/rime-artifacts.md` 和相关构建脚本。

## 数据来源

中文资源来自 Android `app/src/main/assets/dictionaries/rime-ice-enhanced-2026.07.20.zip`，仅规范化归档中的反斜杠路径。没有将 Android `.so` 或 JNI 桥接加入 iOS。

字音和英文文件分别来自 Android `assets/pinyin/pinyin.txt`、`assets/english/en.dict.yaml`。英文文件保留 rime-ice、google-10000-english 与 rime-melt 的来源注释。品牌图片、开发者二维码与打赏二维码沿用 Android 资源。联想基础和增强索引分别原样复制 Android `assets/prediction/base.bin`、`enhanced.bin`，来源哈希见 `config/source-provenance.json`；表情、符号、颜文字及语音处理规则也按该 Android 提交移植。

万象文件沿用 Android 下载地址，预期 420,012,076 字节，SHA-256 为 `099b3e378bfe3d65201a82bfd10b0479602f2492f7328b1ebe97a8d781056340`；尚未完成真机内存、排序质量和下载恢复验收。

发布二进制前仍需按实际制品制作完整依赖清单、对应源码/构建归档，并复核可选模型与全部分发材料。当前没有发布或上传安装包。
