---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA حاليًا في مرحلة العرض المسبق. قم بالتسجيل على
[tuist.dev/qa](https://tuist.dev/qa) للحصول على حق الوصول.
<!-- -->
:::

يعتمد تطوير تطبيقات الجوال عالية الجودة على الاختبارات الشاملة، ولكن الأساليب
التقليدية لها حدودها. الاختبارات الفردية سريعة وفعالة من حيث التكلفة، ولكنها
تغفل سيناريوهات المستخدمين في العالم الحقيقي. يمكن لاختبارات القبول وضمان الجودة
اليدوي سد هذه الثغرات، ولكنها تستهلك موارد كثيرة ولا تتناسب مع الحجم.

يحل وكيل ضمان الجودة في Tuist هذه المشكلة من خلال محاكاة سلوك المستخدم الحقيقي.
فهو يستكشف تطبيقك بشكل مستقل، ويتعرف على عناصر الواجهة، وينفذ تفاعلات واقعية،
ويشير إلى المشكلات المحتملة. تساعدك هذه الطريقة على تحديد الأخطاء ومشكلات
الاستخدام في مرحلة مبكرة من التطوير، مع تجنب الأعباء الإضافية وصعوبات الصيانة
التي تنطوي عليها اختبارات القبول وضمان الجودة التقليدية.

## المتطلبات الأساسية {#prerequisites}

لبدء استخدام Tuist QA، عليك القيام بما يلي:
- قم بإعداد تحميل
  <LocalizedLink href="/guides/features/previews">المعاينات</LocalizedLink> من
  سير عمل PR CI الخاص بك، والتي يمكن للوكيل استخدامها بعد ذلك للاختبار
- <LocalizedLink href="/guides/integrations/gitforge/github">ادمج
  </LocalizedLink> مع GitHub، حتى تتمكن من تشغيل الوكيل مباشرة من PR الخاص بك.

## الاستخدام {#استخدام}

يتم تشغيل Tuist QA حاليًا مباشرة من PR. بمجرد أن يكون لديك معاينة مرتبطة بـ PR،
يمكنك تشغيل وكيل QA عن طريق التعليق `/qa test I want to test feature A` على PR:

![تعليق مشغل QA](/images/guides/features/qa/qa-trigger-comment.png)

يتضمن التعليق رابطًا إلى الجلسة المباشرة حيث يمكنك مشاهدة تقدم وكيل ضمان الجودة
في الوقت الفعلي وأي مشكلات يجدها. بمجرد أن يكمل الوكيل عمله، سينشر ملخصًا
للنتائج في PR:

![ملخص اختبار ضمان الجودة](/images/guides/features/qa/qa-test-summary.png)

كجزء من التقرير في لوحة المعلومات، الذي يرتبط به تعليق العلاقات العامة، ستحصل
على قائمة بالمشكلات والجدول الزمني، حتى تتمكن من فحص كيفية حدوث المشكلة بالضبط:

![QA timeline](/images/guides/features/qa/qa-timeline.png)

يمكنك الاطلاع على جميع عمليات ضمان الجودة التي نقوم بها لتطبيق
<LocalizedLink href="/guides/features/previews#tuist-ios-app">iOS</LocalizedLink>
في لوحة التحكم العامة: https://tuist.dev/tuist/tuist/qa

:::: المعلومات
<!-- -->
يعمل وكيل ضمان الجودة بشكل مستقل ولا يمكن مقاطعته بمطالبات إضافية بمجرد بدء
تشغيله. نحن نقدم سجلات مفصلة طوال فترة التنفيذ لمساعدتك على فهم كيفية تفاعل
الوكيل مع تطبيقك. هذه السجلات مفيدة لتكرار سياق تطبيقك واختبار المطالبات لتوجيه
سلوك الوكيل بشكل أفضل. إذا كان لديك ملاحظات حول أداء الوكيل مع تطبيقك، فيرجى
إخبارنا من خلال [GitHub Issues](https://github.com/tuist/tuist/issues) أو [مجتمع
Slack](https://slack.tuist.dev) أو [منتدى المجتمع](https://community.tuist.dev).
<!-- -->
:::

### سياق التطبيق {#app-context}

قد يحتاج الوكيل إلى مزيد من السياق حول تطبيقك ليتمكن من التنقل فيه بشكل جيد.
لدينا ثلاثة أنواع من سياق التطبيق:
- وصف التطبيق
- الاعتمادات
- مجموعات حجج التشغيل

يمكن تكوين كل هذه الإعدادات في إعدادات لوحة التحكم الخاصة بمشروعك (`Settings` >
`QA`).

#### وصف التطبيق {#app-description}

وصف التطبيق هو لتوفير سياق إضافي حول وظيفة التطبيق وكيفية عمله. هذا حقل نصي طويل
يتم تمريره كجزء من المطالبة عند بدء تشغيل الوكيل. مثال على ذلك:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### الاعتمادات {#credentials}

في حالة احتياج الوكيل إلى تسجيل الدخول إلى التطبيق لاختبار بعض الميزات، يمكنك
توفير بيانات الاعتماد للوكيل لاستخدامها. سيقوم الوكيل بملء بيانات الاعتماد هذه
إذا أدرك أنه يحتاج إلى تسجيل الدخول.

#### مجموعات حجج التشغيل {#launch-argument-groups}

يتم تحديد مجموعات حجج التشغيل بناءً على موجه الاختبار الخاص بك قبل تشغيل الوكيل.
على سبيل المثال، إذا كنت لا تريد أن يقوم الوكيل بتسجيل الدخول بشكل متكرر، مما
يؤدي إلى إهدار الرموز المميزة ودقائق التشغيل، يمكنك تحديد بيانات الاعتماد الخاصة
بك هنا بدلاً من ذلك. إذا أدرك الوكيل أنه يجب أن يبدأ الجلسة بعد تسجيل الدخول،
فسيستخدم مجموعة حجج التشغيل الخاصة ببيانات الاعتماد عند تشغيل التطبيق.

![مجموعات حجج التشغيل](/images/guides/features/qa/launch-argument-groups.png)

هذه الحجج هي حجج تشغيل Xcode القياسية. فيما يلي مثال على كيفية استخدامها لتسجيل
الدخول تلقائيًا:

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
