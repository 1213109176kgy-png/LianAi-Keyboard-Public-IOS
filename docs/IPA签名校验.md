# IPA 签名校验

使用 Xcode 的 Archive / Distribute 或 `xcodebuild archive`、`xcodebuild -exportArchive` 生成安装包。签名证书、导出参数中的团队和描述文件映射保存在本地，不提交证书或私钥。

导出后执行：

```sh
python3 scripts/verify_ios_package.py /absolute/path/to/exported.ipa
```

脚本解压最终 IPA，分别严格验证主 App、每个 `.appex`、framework、动态库和已签名的资源 bundle。任一项失败时退出码非零；不能把失败产物上传分发。也可传入 `.app` 路径检查构建产物。

2026-11-19 的扫码安装失败在真机日志中报告 `MIInstallerErrorDomain Code=13` / `0xe8008017`，定位到键盘扩展的已签名资源发生变化。下载回来的蒲公英 IPA 与本地产物 SHA-256 一致；扩展内 `LianAiCore_LianAiCore.bundle/_CodeSignature/` 的部分文件与扩展资源清单记录的摘要不一致。主 App 的 `codesign --verify --deep --strict` 当时仍返回成功，因此需要上述逐包校验。

签名必须由内到外完成，资源包签名完成后才能签键盘扩展，最后签主 App；后续修改内部文件会使外层签名失效。逐包离线校验也不能代替实际设备安装、证书在线校验和目标设备 UDID 检查。
