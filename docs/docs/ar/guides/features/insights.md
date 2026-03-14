---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# بناء الرؤى {#build-insights}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
<!-- -->
:::

لا ينبغي أن يكون العمل على المشاريع الكبيرة بمثابة عمل روتيني. في الواقع، يجب أن
يكون ممتعًا مثل العمل على مشروع بدأته منذ أسبوعين فقط. أحد أسباب عدم كونه كذلك
هو أن تجربة المطور تتأثر سلبًا مع نمو المشروع. تزداد أوقات البناء وتصبح
الاختبارات بطيئة وغير موثوقة. غالبًا ما يكون من السهل تجاهل هذه المشكلات حتى تصل
إلى نقطة تصبح فيها غير محتملة – ومع ذلك، في تلك المرحلة، يصعب معالجتها. توفر لك
Tuist Insights الأدوات اللازمة لمراقبة حالة مشروعك والحفاظ على بيئة تطوير منتجة
مع توسع نطاق مشروعك.

بعبارة أخرى، تساعدك Tuist Insights في الإجابة عن أسئلة مثل:
- هل زاد وقت البناء بشكل ملحوظ خلال الأسبوع الماضي؟
- هل عمليات البناء الخاصة بي أبطأ في CI مقارنة بالتطوير المحلي؟

على الرغم من أنك ربما تمتلك بعض المقاييس الخاصة بأداء سير عمل التكامل المستمر
(CI)، فقد لا تتمتع بنفس القدر من الرؤية في بيئة التطوير المحلية. ومع ذلك، تعد
أوقات البناء المحلية أحد أهم العوامل التي تساهم في تجربة المطور.

لبدء تتبع أوقات الإنشاء المحلية، يمكنك الاستفادة من الأمر tuist inspect
build` في `عن طريق إضافته إلى الإجراء اللاحق (post-action) في مخططك:

![إجراء لاحق لفحص عمليات
البناء](/images/guides/features/insights/inspect-build-scheme-post-action.png)

:::: المعلومات
<!-- -->
نوصي بتعيين "توفير إعدادات البناء من" على الملف القابل للتنفيذ أو هدف البناء
الرئيسي الخاص بك لتمكين Tuist من تتبع تكوين البناء.
<!-- -->
:::

:::: المعلومات
<!-- -->
إذا كنت لا تستخدم <LocalizedLink href="/guides/features/projects">المشاريع التي
تم إنشاؤها</LocalizedLink>، فلن يتم تنفيذ الإجراء اللاحق في حالة فشل عملية
البناء.
<!-- -->
:::
> 
> تسمح لك ميزة غير موثقة في Xcode بتنفيذها حتى في هذه الحالة. اضبط السمة
> `runPostActionsOnFailure` على `YES` في BuildAction `الخاص بمخططك` في ملف
> `project.pbxproj` ذي الصلة على النحو التالي:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

في حالة استخدام [Mise](https://mise.jdx.dev/)، سيحتاج البرنامج النصي إلى تنشيط
`tuist` في بيئة ما بعد الإجراء:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
بيئة `PATH` متغير البيئة لا يتم توريثه بواسطة إجراء ما بعد المخطط، وبالتالي يجب
عليك استخدام المسار المطلق لـ Mise، والذي سيعتمد على كيفية تثبيت Mise. علاوة على
ذلك، لا تنسَ توريث إعدادات البناء من هدف في مشروعك بحيث يمكنك تشغيل Mise من
الدليل الذي يشير إليه $SRCROOT.
<!-- -->
:::


يتم الآن تتبع عمليات البناء المحلية الخاصة بك طالما أنك مسجل الدخول إلى حساب
Tuist الخاص بك. يمكنك الآن الوصول إلى أوقات البناء الخاصة بك في لوحة تحكم Tuist
ومشاهدة تطورها بمرور الوقت:


:::: إكرامية
<!-- -->
للوصول بسرعة إلى لوحة التحكم، قم بتشغيل `tuist project show --web` من واجهة سطر
الأوامر.
<!-- -->
:::

![لوحة التحكم مع إحصاءات
البناء](/images/guides/features/insights/builds-dashboard.png)

## المشاريع التي تم إنشاؤها {#generated-projects}

:::: المعلومات
<!-- -->
تتضمن المخططات التي يتم إنشاؤها تلقائيًا الإجراء اللاحق `tuist inspect build`.
<!-- -->
:::
> 
> إذا لم تكن مهتمًا بتتبع الإحصاءات في مخططاتك التي يتم إنشاؤها تلقائيًا، فقم
> بتعطيلها باستخدام خيار الإنشاء
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

إذا كنت تستخدم مشاريع تم إنشاؤها باستخدام مخططات مخصصة، فيمكنك إعداد إجراءات
لاحقة للحصول على إحصاءات البناء:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

إذا كنت لا تستخدم Mise، فيمكن تبسيط البرامج النصية إلى:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## التكامل المستمر {#continuous-integration}

لتتبع إحصاءات البناء على CI، ستحتاج إلى التأكد من أن CI الخاص بك
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">مصادق
عليه</LocalizedLink>.

بالإضافة إلى ذلك، ستحتاج إلى:
- استخدم الأمر <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> عند استدعاء `xcodebuild` actions.
- أضف `-resultBundlePath` إلى استدعاء `xcodebuild`.

عندما يقوم `xcodebuild` ببناء مشروعك بدون `-resultBundlePath` ، لا يتم إنشاء
ملفات سجل النشاط وحزمة النتائج المطلوبة. تتطلب الإجراء اللاحق `tuist inspect
build` هذه الملفات لتحليل عمليات البناء الخاصة بك.
