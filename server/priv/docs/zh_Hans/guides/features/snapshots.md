---
{
  "title": "快照",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "在 Xcode 和 Gradle 项目中捕获视觉回归：Tuist 会存储你的快照图像，将每个拉取请求与其基线进行比较，并允许你从仪表板或拉取请求中批准或拒绝更改。"
}
---
# 快照 {#snapshots}

> [!IMPORTANT]
> **仅限邀请**
>
> 快照功能目前仅限邀请使用。[联系我们](mailto:contact@tuist.dev)或在 [社区 Slack](https://slack.tuist.dev) 中留言，为你的账户申请访问权限。

快照测试将你的 UI 渲染为图片，并与参考图片进行比较，以捕捉视觉回归问题。无需将这些参考图片提交到代码仓库，你只需将每次测试运行渲染的图片上传到 Tuist。Tuist 会将它们与**基线**进行比较，在仪表板中显示变更内容，并在有人批准这些变更之前使运行失败。

- Git 中不包含参考图片，因此克隆体积更小，也无需解决 PNG 文件的冲突。
- 审阅者可以在代码旁边查看变更：并排对比、差异视图，或使用滑动擦除和洋葱皮叠加效果。
- 你可以在仪表板或拉取请求中批准或拒绝变更，一旦分支合并，该批准将成为新的基线。

## 工作原理 {#how-it-works}

1. 你的测试会渲染图片，例如每个 SwiftUI 或 Compose 预览。
2. Tuist CLI 或 Gradle 插件会将它们作为当前提交的**快照构建**进行上传。
3. Tuist 会选择基线：即你的默认分支在你当前分支起始提交处的构建。
4. 每张图片都会与其基线进行比较，并标记为已变更、新增、移除或未变更。
5. 构建将获得以下判定：

| 判定 | 运行 | 条件 |
| --- | --- | --- |
| 基线 | 通过 | 该构建来自默认分支，因此后续构建将以其作为比较对象。 |
| 已通过 | 通过 | 没有图片发生变更或被移除。新增图片无需审阅。 |
| 需要审阅 | 失败 | 图片发生变更或被移除，且尚未有人审阅。 |
| 已批准 | 通过 | 有人已批准这些变更。 |
| 已拒绝 | 失败 | 有人已拒绝这些变更。 |

构建会在一个**集合**内进行比较，例如 `ios-iphone` 或 `android-phone`。为每种设备配置使用一个集合，这样不同尺寸渲染的图片就不会相互比较。

## 设置 {#set-up}

为你的项目选择集成方式：

<.home_cards>
  <.home_card
    title="Xcode"
    details="使用 tuist xcodebuild test 对 Xcode 项目中的每个 SwiftUI 预览进行快照。"
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="生成的项目"
    details="使用 tuist test 对 Tuist 生成的项目中的每个 SwiftUI 预览进行快照。"
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="使用 Tuist Gradle 插件对每个 Compose 预览进行快照，或上传 Paparazzi 和 Roborazzi 记录的内容。"
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## 在仪表板中审阅变更 {#dashboard}

每个快照构建在项目仪表板的**测试 → 快照**下都有一个页面。它显示构建的判定、分支、提交、拉取请求和基线，并按状态和组列出图片。使用**批准变更**或**拒绝变更**来审阅构建。你可以稍后更改审阅结果。

![需要审阅的快照构建，变更后的图片与其基线并排显示](/images/guides/features/snapshots/review.png)

在**并排**、**差异**（突出显示变更的像素）、**滑动擦除**（在基线和新图片之间滑动）以及**洋葱皮**（将一张图片淡入另一张）之间切换。每张图片都可以全屏查看。

![滑动擦除模式，在基线和新图片之间滑动](/images/guides/features/snapshots/wipe.png)

## 在拉取请求中审阅变更 {#pull-request}

安装<.localized_link href="/guides/integrations/gitforge/github">GitHub 应用</.localized_link>后，拉取请求的每个快照构建都会获得一个名为 `tuist/snapshots (<set>)` 的检查。当变更需要审阅，或者审阅者拒绝变更后，如果该检查是必需的，它将失败并阻止合并：

![拉取请求的合并按钮区域，由于变更被拒绝，快照检查失败](/images/guides/features/snapshots/github-pr-checks.png)

该检查会统计集合中变更、新增和移除的图片数量，并提供指向仪表板中构建的链接。无需离开 GitHub，即可从检查页面批准或拒绝变更。检查会更新为审阅者的姓名，被拒绝的构建之后仍可被批准。

![变更被拒绝后 GitHub 上的快照检查，带有批准按钮](/images/guides/features/snapshots/github-check-run.png)

批准不会重新运行你的测试：它会直接通过检查。只要同一分支的后续构建具有完全相同的变更，它们就会保留该批准状态，因此重新运行 CI 或推送不涉及已审阅图片的提交也会通过。对图片的任何其他变更都需要新的审阅。一旦分支合并，默认分支的构建将成为新的基线。
