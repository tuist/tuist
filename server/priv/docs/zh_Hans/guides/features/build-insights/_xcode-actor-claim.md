## 报告参与者声明 {#report-actor-claim}

仅当你将 `TUIST_ACTOR_ID` 显式设置为组织范围内的标签（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）时，创建报告的请求才会包含可选的 `x-tuist-actor-id` 标头。默认情况下不会发送任何标签，Tuist 也不会检测操作系统用户名。空的 `TUIST_ACTOR_ID` 会省略报告的标识符，但不会移除基于凭据的已验证身份。标识符必须是 1–128 字节的非空格可打印 ASCII 字符；无效的覆盖会被省略且不会回退。如果自定义代理拒绝不熟悉的标头，请使用空的环境覆盖来退出。

已验证的个人凭据优先；否则，客户端报告的标识符将显示为 **未验证**，且绝不会授予权限或自动链接到用户。任何能够查看项目报告的人都可以看到这些标识符，包括项目公开时的公众查看者，并且它们会包含在数据导出中，因此请勿包含机密信息。这适用于构建、测试和命令事件报告。旧服务器会忽略该可选标头，新服务器则接受不带该标头的旧客户端。没有标识符的新共享令牌报告会显示 **未知**，而不是发布组织；历史报告保留其先前的归属。构建和测试列表会区分已验证用户与未验证的报告标识符。除非自托管实例显式启用无凭据报告且客户端发现该策略，否则仍需要身份验证。

### Scheme 后操作 {#actor-claim-post-actions}

参与者声明默认处于禁用状态。要为 Scheme 后操作配置一个声明，请在该脚本中设置 `TUIST_ACTOR_ID`，而不是依赖 shell 导出。从 Dock 启动的 Xcode 不会继承 `~/.zshrc` 中的变量。要使用 Homebrew 显式抑制已配置的声明，请使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 时，在 Mise 加载其环境后覆盖该值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用显式标签而非空值来选择加入。
