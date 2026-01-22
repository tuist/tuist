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
- أ <LocalizedLink href="/guides/server/accounts-and-projects">حساب ومشروع تويست
  <LocalizedLink href="/guides/server/accounts-and-projects">تويست</LocalizedLink>
<!-- -->
:::

لا ينبغي أن يبدو العمل على المشاريع الكبيرة عملاً روتينيًا. في الواقع، يجب أن
يكون ممتعًا مثل العمل على مشروع بدأته قبل أسبوعين فقط. أحد الأسباب التي تجعل
الأمر ليس كذلك هو أنه كلما كبر المشروع، كلما تأثرت تجربة المطور. حيث تزداد أوقات
البناء وتصبح الاختبارات بطيئة ومتعثرة. غالبًا ما يكون من السهل التغاضي عن هذه
المشكلات إلى أن تصل إلى نقطة تصبح فيها غير محتملة - ولكن عند هذه النقطة، من
الصعب معالجتها. توفّر لك Tuist Insights الأدوات اللازمة لمراقبة سلامة مشروعك
والحفاظ على بيئة مطوّر منتجة للمطوّرين مع توسع مشروعك.

بعبارة أخرى، تساعدك رؤى تويست إنسايتس على الإجابة عن أسئلة مثل:
- هل زاد وقت البناء بشكل ملحوظ في الأسبوع الماضي؟
- هل عمليات الإنشاء الخاصة بي أبطأ على CI مقارنة بالتطوير المحلي؟

في حين أنه من المحتمل أن يكون لديك بعض المقاييس لأداء عمليات سير عمل CI، فقد لا
يكون لديك نفس الرؤية في بيئة التطوير المحلية. ومع ذلك، فإن أوقات البناء المحلية
هي أحد أهم العوامل التي تساهم في تجربة المطور.

لبدء تتبع أوقات الإنشاء المحلي، يمكنك الاستفادة من الأمر `tuist inspect build`
من خلال إضافته إلى الإجراء اللاحق لمخططك:

![الإجراء اللاحق لفحص الإنشاءات]
(/images/guides/features/insights/inspect-build-scheme-post-action.png)

:::: المعلومات
<!-- -->
نوصي بتعيين "توفير إعدادات الإنشاء من" إلى الملف القابل للتنفيذ أو هدف الإنشاء
الرئيسي الخاص بك لتمكين Tuist من تتبع تكوين الإنشاء.
<!-- -->
:::

:::: المعلومات
<!-- -->
إذا كنت لا تستخدم <LocalizedLink href="/guides/features/projects">المشاريع التي
تم إنشاؤها </LocalizedLink>، فلن يتم تنفيذ إجراء ما بعد المخطط في حالة فشل
الإنشاء.
<!-- -->
:::
> 
> تسمح لك ميزة غير موثقة في Xcode بتنفيذها حتى في هذه الحالة. قم بتعيين السمة
> `runPostActionsOnFailure` إلى `نعم` في ملف `BuildAction` الخاص بالمخطط الخاص
> بك في ملف `project.pbxproj` ذي الصلة على النحو التالي:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

في حال كنت تستخدم [Mise] (https://mise.jdx.dev/)، سيحتاج البرنامج النصي الخاص بك
إلى تنشيط `tuist` في بيئة ما بعد العمل:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
لا يتم توريث متغير البيئة الخاص ببيئتك `PATH` من خلال إجراء ما بعد المخطط،
وبالتالي عليك استخدام المسار المطلق لـ Mise، والذي سيعتمد على كيفية تثبيت Mise.
علاوةً على ذلك، لا تنسَ أن ترث إعدادات الإنشاء من هدف في مشروعك بحيث يمكنك تشغيل
Mise من الدليل الذي يشير إليه $SRCROOT.
<!-- -->
:::


يتم الآن تتبع عمليات الإنشاء المحلية الخاصة بك طالما أنك مسجّل الدخول إلى حسابك
في Tuist. يمكنك الآن الوصول إلى أوقات الإنشاءات الخاصة بك في لوحة معلومات Tuist
ومعرفة كيفية تطورها بمرور الوقت:


:::: إكرامية
<!-- -->
للوصول بسرعة إلى لوحة التحكم، قم بتشغيل `tuist project show --web` من CLI.
<!-- -->
:::

![لوحة معلومات مع رؤى البناء]
(/images/guides/features/insights/builds-dashboard.png)

## المشاريع التي تم إنشاؤها {#generated-projects}

:::: المعلومات
<!-- -->
تتضمن المخططات التي يتم إنشاؤها تلقائيًا المخططات التي يتم إنشاؤها تلقائيًا
`tuist فحص البناء` ما بعد العمل.
<!-- -->
:::
> 
> إذا لم تكن مهتمًا بتتبع الرؤى في المخططات التي يتم إنشاؤها تلقائيًا، فعليك
> تعطيلها باستخدام خيار إنشاء
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">
> إنشاء رؤى معطلة</LocalizedLink>.

إذا كنت تستخدم المشاريع التي تم إنشاؤها باستخدام مخططات مخصصة، يمكنك إعداد
إجراءات لاحقة لرؤى الإنشاء:

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

إذا كنت لا تستخدم Mise، يمكن تبسيط نصوصك البرمجية إلى:

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

لتتبع رؤى الإنشاء على CI، ستحتاج إلى التأكد من أن CI الخاص بك هو
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">
مصادق عليه</LocalizedLink>.

بالإضافة إلى ذلك، ستحتاج إما إلى
- استخدم الأمر <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> عند استدعاء `xcodebuild` الإجراءات.
- أضف `-resultBundleBundlePath` إلى استدعاء `xcodebuild`.

عندما يقوم `xcodebuild` ببناء مشروعك بدون `-resultBundlePath` ، لا يتم إنشاء
ملفات سجل النشاط المطلوبة وملفات حزمة النتائج. يتطلب `tuist فحص الإنشاء` ما بعد
الإجراء هذه الملفات لتحليل الإنشاءات الخاصة بك.
