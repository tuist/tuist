---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# رؤى الاختبار {#test-insights}

:::: متطلبات التحذير
<!-- -->
- حساب <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  والمشروع</LocalizedLink>
<!-- -->
:::

تساعدك رؤى الاختبار على مراقبة صحة مجموعة الاختبارات الخاصة بك من خلال تحديد
الاختبارات البطيئة أو فهم عمليات تشغيل CI الفاشلة بسرعة. مع نمو مجموعة
الاختبارات الخاصة بك، يصبح من الصعب بشكل متزايد اكتشاف الاتجاهات مثل الاختبارات
التي تتباطأ تدريجياً أو الفشل المتقطع. توفر لك Tuist Test Insights الرؤية التي
تحتاجها للحفاظ على مجموعة اختبارات سريعة وموثوقة.

باستخدام Test Insights، يمكنك الإجابة عن أسئلة مثل:
- هل أصبحت اختباراتي أبطأ؟ أي منها؟
- ما الاختبارات غير الموثوقة والتي تحتاج إلى اهتمام؟
- لماذا فشل تشغيل CI الخاص بي؟

## الإعداد {#setup}

لبدء تتبع اختباراتك، يمكنك الاستفادة من الأمر `tuist inspect test` بإضافته إلى
إجراء ما بعد الاختبار في مخططك:

![إجراء لاحق لفحص
الاختبارات](/images/guides/features/insights/inspect-test-scheme-post-action.png)

في حالة استخدام [Mise](https://mise.jdx.dev/)، سيحتاج البرنامج النصي إلى تنشيط
`tuist` في بيئة ما بعد الإجراء:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
بيئة `PATH` متغير البيئة لا يتم توريثه بواسطة إجراء ما بعد المخطط، وبالتالي يجب
عليك استخدام المسار المطلق لـ Mise، والذي سيعتمد على كيفية تثبيت Mise. علاوة على
ذلك، لا تنسَ توريث إعدادات البناء من هدف في مشروعك بحيث يمكنك تشغيل Mise من
الدليل الذي يشير إليه $SRCROOT.
<!-- -->
:::

يتم الآن تتبع اختباراتك طالما أنك مسجل الدخول إلى حساب Tuist الخاص بك. يمكنك
الوصول إلى نتائج اختباراتك في لوحة معلومات Tuist ومشاهدة تطورها بمرور الوقت:

![لوحة معلومات مع رؤى
الاختبار](/images/guides/features/insights/tests-dashboard.png)

بصرف النظر عن الاتجاهات العامة، يمكنك أيضًا التعمق في كل اختبار على حدة، مثل عند
تصحيح الأخطاء أو الاختبارات البطيئة على CI:

![تفاصيل الاختبار](/images/guides/features/insights/test-detail.png)

## المشاريع التي تم إنشاؤها {#generated-projects}

:::: المعلومات
<!-- -->
تتضمن المخططات التي يتم إنشاؤها تلقائيًا بشكل تلقائي `tuist inspect test`
post-action.
<!-- -->
:::
> 
> إذا لم تكن مهتمًا بتتبع رؤى الاختبار في مخططاتك التي تم إنشاؤها تلقائيًا، فقم
> بتعطيلها باستخدام خيار الإنشاء
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>.

إذا كنت تستخدم مشاريع تم إنشاؤها باستخدام مخططات مخصصة، فيمكنك إعداد إجراءات
لاحقة للحصول على رؤى الاختبار:

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
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

إذا كنت لا تستخدم Mise، فيمكن تبسيط البرامج النصية إلى:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## التكامل المستمر {#continuous-integration}

لتتبع رؤى الاختبار على CI، ستحتاج إلى التأكد من أن CI الخاص بك
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">مصادق
عليه</LocalizedLink>.

بالإضافة إلى ذلك، ستحتاج إلى:
- استخدم الأمر <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> عند استدعاء `xcodebuild` actions.
- أضف `-resultBundlePath` إلى استدعاء `xcodebuild`.

عندما يقوم `xcodebuild` باختبار مشروعك بدون `-resultBundlePath` ، لا يتم إنشاء
ملفات حزمة النتائج المطلوبة. تتطلب إجراءات ما بعد الاختبار `tuist inspect test`
هذه الملفات لتحليل اختباراتك.
