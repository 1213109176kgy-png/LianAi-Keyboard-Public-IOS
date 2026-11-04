# iOS 键盘内语音输入：实现核查

> 2026-11-04 更新：已删除此前自行设置的“闲置 5 分钟关闭”，一次开启后不再因闲置停止。当前会话边界及回归见 [语音持续会话修复](../语音持续会话修复.md)。
日期：2026-11-03。目标交互：长按空格说话、松开识别、上滑取消；识别文字回填当前输入位置，不跳到主 App 完成每一次录音。

## 可确认的事实

- 搜狗官方 iOS 更新记录确认支持键盘内免跳转语音。它没有在该页面公开录音进程和内部接口，因此不能把某个第三方方案当作搜狗、讯飞或微信输入法的源码结论。
- Apple 的自定义键盘资料明确限制扩展直接使用麦克风。系统在键盘下方提供的听写入口，与输入法自己实现的空格长按入口不同；`hasDictationKey` 仅声明是否自带听写按钮，不会授予麦克风权限，也不是启动系统听写的方法。
- Apple 支持主 App 的音频会话在进入后台后继续录音，需要配置 audio 后台模式。
- 可核查的 Ara 源码实现了前台开启连续音频引擎、待机时丢弃音频、键盘请求时才处理当前语音、通过 App Group 交还文本的路径。Wispr Flow 官方也说明了后台语音会话和超时关闭机制。这证明键盘内免逐次跳转可以实现；不能证明第三方键盘可以在主 App 完全未运行时直接打开麦克风。

## 本项目实现

未引入或复制 Ara 代码，独立使用系统 AVAudioEngine、Apple Speech 和项目已有 App Group 实现：

1. 用户首次在主 App 开启语音会话，授予麦克风和语音识别权限。界面说明系统橙色指示灯、待机处理方式与关闭时间。
2. 持续音频引擎保持可用；`VoiceAudioGate` 在没有识别请求时直接丢弃回调音频。音频不进入共享文件，也不进入待机识别任务。
3. 键盘长按空格写入 start 命令；主 App 开始本次音频采集与识别。已配置 MiMo/官方通道时将硬件音频转为规范 WAV，通过现有 API 识别，录音中约每 1.4 秒请求中间稿；Apple 路径使用 Speech 流式识别。松开写入 finish，上滑写入 cancel。
4. 点麦克风提供相同的键盘内界面，通过完成/取消控制；支持键盘内关闭整个语音会话。
5. 命令使用独立原子文件队列，避免快速松手覆盖尚未处理的开始命令。每个命令带会话、录音请求编号和有效时间。
6. 结果只交给匹配请求、原输入框、原光标上下文、原模式、原账号和原草稿的键盘。识别期间切换输入框/光标、收起键盘会取消；失联超过 4 秒由服务端取消该次语音。
7. 普通模式回填聊天输入框；超会说、帮你回手动输入模式回填各自内部草稿，不改宿主文本。不会自动发送。
8. 单次最长 60 秒，闲置 5 分钟关闭音频会话。电话/Siri 音频中断、设备切换等终止会话，需要重新开启。主 App 被系统结束或手机重启后，也需要重新激活。
9. 识别优先沿用已配置的 MiMo ASR 或官方登录通道，未配置时提供 Apple Speech。保留原单次录音、润色与翻译工具，两个录音路径不会同时启用。账号或 ASR 配置变化后终止旧会话，重新开启后采用新配置。

## 验证口径

自动化中的语音 fixture 只替换音频/识别边界，真实运行主 App 服务、文件队列、独立键盘扩展、长按/滑动手势和结果插入。它能验证交互和防串输入框逻辑，不能代表真实麦克风识别率。

另设不使用 fixture 的原生权限和音频引擎测试。真实说话识别率、后台生命周期、电话/蓝牙中断和耗电仍需签名真机验收。当前用户明确选择先完成可运行版本与模拟器验收，最终记录必须保留这些边界。

## 一手来源

- [搜狗 iOS 官方更新记录](https://shouji.sogou.com/log.php?see=ios)
- [Apple 自定义键盘](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Apple 自定义键盘界面及 hasDictationKey](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)
- [Apple 后台录音](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)
- [Ara 开源源码与架构说明](https://github.com/sebastiendb/Ara/tree/e7a2cc58fa7d7e9fb95a29b0d6a49adb740ba0a4)（调研提交 e7a2cc58fa7d7e9fb95a29b0d6a49adb740ba0a4）
- [Wispr Flow 后台音频会话说明](https://docs.wisprflow.ai/articles/8415579688-why-wispr-flow-doesn-t-pause-background-audio-on-iphone-ios)
