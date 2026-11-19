## 私有网络上的免凭证报告 {#network-trusted-publishing}

自托管部署可以允许开发者在不登录的情况下发布已完成的报告。操作员必须在实例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 并按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自托管指南</.localized_link> 中的说明重启实例。这适用于所有受支持的项目；仪表板中没有相关设置。请在你的 scheme 后操作或终端使用的环境中配置自托管 URL 和项目。当缺少凭证时，CLI 会自动发现实例策略：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在确实缺少凭证的情况下，活动日志和 XCResult 包会在本地解析并作为结构化报告发送。不会提交原始归档文件、附件、覆盖率/历史记录上传、远程处理器、分片引用或选择性执行证据。报告仍然可见，但无法更新经过身份验证的测试用例状态或触发隔离/失败自动化。仪表板和其他特权命令仍然需要登录。除非实例单独启用了网络信任的缓存访问或已提供凭证，否则请保持缓存集成处于禁用状态。

现有凭证保持已认证状态。无效、损坏、空白或被拒绝刷新的凭证会以安全失败方式处理并保留在磁盘上，因此后续命令不会静默变为未签名状态。请重新登录或显式注销，作为一种有意的恢复操作。在升级免凭证客户端之前，请将每个服务器副本升级到支持发现的版本，并配置最终服务器 URL 且不包含重定向。不支持发现的旧服务器、已禁用的实例以及发现失败的情况仍然需要身份验证。无需客户端选择加入。独立设置 `TUIST_ACTOR_ID=""` 以省略配置的 actor 声明；已验证的凭证身份不受影响。
