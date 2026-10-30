---
{
  "title": "调试",
  "titleTemplate": ":title · 贡献者 · Tuist",
  "description": "使用编码代理和本地运行来调试 Tuist 中的问题。"
}
---
# 调试 {#debugging}

开源带来实际优势：代码公开可用，你可以在本地运行，并利用编码智能体更快地解答问题、调试代码库中的潜在缺陷。

如果在调试过程中发现文档缺失或不完整，请更新 `docs/` 下的英文文档并提交 PR。

## 在 CI 上捕获线程转储 {#thread-dump-ci}

当 CLI 间歇性卡顿时，你可以在不停止进程的情况下捕获线程转储。启用信号处理程序并向正在运行的 `tuist` 进程发送 `SIGUSR1`。

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

如果未设置 `TUIST_THREAD_DUMP_SAMPLE`，处理程序会打印当前线程堆栈。输出写入 stderr，因此会出现在 CI 日志中。

## 使用编码智能体 {#use-coding-agents}

编码智能体适用于：

- 扫描代码库，定位实现特定行为的位置。
- 在本地复现问题并快速迭代。
- 追踪输入在 Tuist 中的流转路径，以找到根本原因。

分享尽可能最小化的复现步骤，并将智能体指向具体组件（CLI、服务器、缓存、文档或手册）。范围越聚焦，调试过程就越快、越准确。

### 常用提示词 (FNP) {#frequently-needed-prompts}

#### 项目生成结果不符合预期 {#unexpected-project-generation}

项目生成的结果与预期不符。针对位于 `/path/to/project` 的项目运行 Tuist CLI，以了解发生这种情况的原因。追踪生成器流水线，并指出负责该输出的代码路径。

#### 生成项目中可复现的缺陷 {#reproducible-bug-in-generated-projects}

这看起来像是生成项目中的一个缺陷。在 `examples/` 下创建一个可复现的项目，参考现有示例。添加一个失败的验收测试，仅选择该测试并通过 `xcodebuild` 运行，修复问题后重新运行测试以确认通过，然后提交 PR。
