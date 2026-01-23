---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不稳定的测试{#flaky-tests}

警告要求
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">测试洞察</LocalizedLink>必须进行配置
<!-- -->
:::

不稳定测试是指使用相同代码多次运行时产生不同结果（通过或失败）的测试。它们会削弱对测试套件的信任，并浪费开发者排查虚假失败的时间。Tuist能自动检测不稳定测试，并帮助您长期追踪其状态。

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## 如何实现不稳定检测{#how-it-works}

Tuist通过两种方式检测不稳定的测试：

### 测试重试{#test-retries}

当您使用Xcode的重试功能运行测试（通过`-retry-tests-on-failure` 或`-test-iterations`
执行）时，Tuist会分析每次尝试的结果。若某项测试在部分尝试中失败而在其他尝试中通过，则会被标记为不稳定测试。

例如，若测试首次失败但重试通过，Tuist会将其记录为不稳定测试。

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不稳定测试用例详情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨运行检测{#cross-run-detection}

即使不进行测试重试，Tuist也能通过比较同一提交下不同CI运行结果来检测不稳定测试。若某测试在一次CI运行中通过，而在同一提交的另一次运行中失败，则两次运行均会被标记为不稳定。

这对于捕捉不稳定的测试特别有用——这类测试失败不够稳定，无法通过重试捕获，却仍会导致持续集成间歇性失败。

## 管理不稳定的测试{#managing-flaky-tests}

### 自动清除

Tuist会自动清除连续14天未出现异常的测试项的"不稳定"标记。此机制确保已修复的测试不会永久保留不稳定状态。

### 手动管理

您还可从测试用例详情页手动标记或取消标记测试为不稳定。此功能适用于以下情况：
- 在修复已知不稳定测试时，需明确标注该情况
- 因基础设施问题导致测试被错误标记

## Slack通知{#slack-notifications}

通过在 Slack 集成中设置
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">不稳定测试警报</LocalizedLink>，当测试出现不稳定情况时立即收到通知。
