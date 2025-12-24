---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# ضمان الجودة {#qa}

::: warning EARLY PREVIEW
<!-- -->
تويست QA حاليًا في مرحلة المعاينة المبكرة. سجّل في [tuist.dev.dev/qa]
(https://tuist.dev/qa) للحصول على إمكانية الوصول.
<!-- -->
:::

يعتمد تطوير تطبيقات الأجهزة المحمولة عالية الجودة على الاختبار الشامل، لكن
الأساليب التقليدية لها قيود. اختبارات الوحدة سريعة وفعالة من حيث التكلفة، ومع
ذلك فهي تغفل سيناريوهات المستخدم في العالم الحقيقي. يمكن لاختبار القبول واختبار
ضمان الجودة اليدوي أن يلتقطا هذه الثغرات، لكنهما يستهلكان موارد كثيرة ولا
يتوسعان بشكل جيد.

يحل وكيل ضمان الجودة من تويست هذا التحدي من خلال محاكاة سلوك المستخدم الحقيقي.
فهو يستكشف تطبيقك بشكل مستقل، ويتعرف على عناصر الواجهة، وينفذ تفاعلات واقعية،
ويحدد المشكلات المحتملة. يساعدك هذا النهج على تحديد الأخطاء ومشاكل قابلية
الاستخدام في وقت مبكر من التطوير مع تجنب أعباء الصيانة والنفقات الزائدة لاختبار
القبول التقليدي واختبار ضمان الجودة.

## المتطلبات الأساسية {#prerequisites}

لبدء استخدام ضمان الجودة من تويست، تحتاج إلى
- قم بإعداد تحميل <LocalizedLink href="/guides/features/previews">مراجعات</LocalizedLink> من سير عمل العلاقات العامة CI، والتي يمكن للوكيل استخدامها بعد ذلك للاختبار
- <LocalizedLink href="/guides/integrations/gitforge/github">دمج</LocalizedLink> مع GitHub، حتى تتمكن من تشغيل الوكيل مباشرةً من علاقاتك العامة

## الاستخدام {#usage}

يتم تشغيل ضمان الجودة في تويست حاليًا مباشرةً من العلاقات العامة. بمجرد أن يكون
لديك معاينة مرتبطة بعلاقاتك العامة، يمكنك تشغيل عامل ضمان الجودة عن طريق التعليق
`/qa test أريد اختبار الميزة A` على العلاقات العامة:

![تعليق مشغل ضمان الجودة] (/images/guides/features/qa/qa-trigger-comment.png)

يتضمن التعليق رابطًا للجلسة المباشرة حيث يمكنك رؤية تقدم وكيل ضمان الجودة في
الوقت الفعلي وأي مشكلات يعثر عليها. وبمجرد أن يكمل الوكيل تشغيله، سيقوم بنشر
ملخص للنتائج إلى العلاقات العامة:

![ملخص اختبار ضمان الجودة] (/images/guides/features/qa/qa-test-summary.png)

كجزء من التقرير الموجود في لوحة التحكم، والذي يرتبط به تعليق العلاقات العامة،
ستحصل على قائمة بالمشكلات وجدول زمني، حتى تتمكن من فحص كيفية حدوث المشكلة
بالضبط:

![جدول زمني لضمان الجودة] (/images/guides/features/qa/qa-timeline.png)

يمكنك الاطلاع على جميع عمليات ضمان الجودة التي نقوم بها لتطبيق <LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS</LocalizedLink> الخاص بنا في لوحة التحكم العامة لدينا: https://tuist.dev/tuist/tuist/qa

::: info
<!-- -->
يعمل وكيل ضمان الجودة بشكل مستقل ولا يمكن مقاطعته بمطالبات إضافية بمجرد بدء
التشغيل. نحن نقدم سجلات مفصلة طوال فترة التنفيذ لمساعدتك على فهم كيفية تفاعل
الوكيل مع تطبيقك. هذه السجلات ذات قيمة لتكرار سياق تطبيقك واختبار المطالبات
لتوجيه سلوك الوكيل بشكل أفضل. إذا كانت لديك ملاحظات حول كيفية أداء الوكيل مع
تطبيقك، يُرجى إعلامنا من خلال [مشكلات
GitHub](https://github.com/tuist/tuist/issues) أو [مجتمع
Slack](https://slack.tuist.dev) أو [منتدى المجتمع](https://community.tuist.dev).
<!-- -->
:::

### سياق التطبيق {#app-context}

قد يحتاج الوكيل إلى مزيد من السياق حول تطبيقك ليتمكن من التنقل فيه بشكل جيد.
لدينا ثلاثة أنواع من سياق التطبيق:
- وصف التطبيق
- أوراق الاعتماد
- إطلاق مجموعات الحجج

يمكن تهيئتها جميعًا في إعدادات لوحة التحكم الخاصة بمشروعك (`الإعدادات` > `QA`).

#### وصف التطبيق {#app-description}

وصف التطبيق هو لتوفير سياق إضافي حول ما يفعله تطبيقك وكيفية عمله. هذا حقل نصي
طويل يتم تمريره كجزء من المطالبة عند بدء تشغيل الوكيل. مثال يمكن أن يكون:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### أوراق الاعتماد {#credentials}

في حال احتاج الوكيل إلى تسجيل الدخول إلى التطبيق لاختبار بعض الميزات، يمكنك
توفير بيانات اعتماد للوكيل لاستخدامها. سيقوم الوكيل بملء بيانات الاعتماد هذه إذا
أدرك أنه بحاجة إلى تسجيل الدخول.

#### إطلاق مجموعات الحجج {#launch-argument-groups}

يتم تحديد مجموعات وسيطة التشغيل بناءً على مطالبة الاختبار الخاصة بك قبل تشغيل
الوكيل. على سبيل المثال، إذا كنت لا تريد أن يقوم الوكيل بتسجيل الدخول بشكل
متكرر، مما يؤدي إلى إهدار الرموز المميزة ودقائق التشغيل، يمكنك تحديد بيانات
الاعتماد الخاصة بك هنا بدلاً من ذلك. إذا أدرك الوكيل أنه يجب أن يبدأ الجلسة
بتسجيل الدخول، فسيستخدم مجموعة وسيطة تشغيل بيانات الاعتماد عند تشغيل التطبيق.

![إطلاق مجموعات الحجج] (/images/guides/features/qa/launch-argument-groups.png)

وسيطات التشغيل هذه هي وسيطات تشغيل Xcode القياسية الخاصة بك. إليك مثال على كيفية
استخدامها لتسجيل الدخول تلقائيًا:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
