---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# تكامل Slack {#slack}

إذا كانت مؤسستك تستخدم Slack، يمكنك دمج Tuist لإظهار الرؤى مباشرةً في قنواتك.
هذا يحول المراقبة من شيء يجب على فريقك أن يتذكر القيام به إلى شيء يحدث فقط. على
سبيل المثال، يمكن أن يتلقى فريقك ملخصات يومية عن أداء الإنشاء أو معدلات الوصول
إلى ذاكرة التخزين المؤقت أو اتجاهات حجم الحزمة.

## الإعداد {#setup}

### ربط مساحة عمل Slack الخاصة بك {#connect-workspace}

أولاً، قم بتوصيل مساحة عمل Slack بحسابك على Tuist في علامة التبويب
`Integrations`:

![صورة تُظهر علامة تبويب عمليات التكامل مع اتصال Slack]
(/images/guides/integrations/slack/integrations.png)

انقر **قم بتوصيل سلاك** لتفويض تويست بنشر الرسائل إلى مساحة العمل الخاصة بك.
سيؤدي ذلك إلى إعادة توجيهك إلى صفحة تفويض Slack حيث يمكنك الموافقة على الاتصال.

> [!ملاحظة] موافقة مسؤول سلاك إذا كانت مساحة عمل سلاك الخاصة بك تقيد عمليات
> تثبيت التطبيقات، فقد تحتاج إلى طلب الموافقة من مسؤول سلاك. سيرشدك Slack خلال
> عملية طلب الموافقة أثناء التفويض.

### تقارير المشروع {#project-reports}

After connecting Slack, configure reports for each project in the project
settings' notifications tab:

![An image that shows the notifications settings with Slack report
configuration](/images/guides/integrations/slack/notifications-settings.png)

يمكنك التهيئة:
- **القناة**: حدد قناة Slack التي تتلقى التقارير
- **الجدول**: اختر أيام الأسبوع لتلقي التقارير
- **الوقت**: ضبط الوقت من اليوم

بمجرد التهيئة، يرسل تويست تقارير يومية تلقائية إلى قناة Slack التي اخترتها:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Alert rules {#alert-rules}

Get notified in Slack with alert rules when key metrics significantly regress to
help you catch slower builds, cache degradation, or test slowdowns as soon as
possible, minimizing the impact on your team's productivity.

To create an alert rule, go to your project's notification settings and click
**Add alert rule**:

يمكنك التهيئة:
- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit
  rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: Where to send the alert

For example, you might create an alert that triggers when the p90 build duration
increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack
channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD After an alert triggers, it won't fire again for the
> same rule for 24 hours. This prevents notification fatigue when a metric stays
> elevated.

## التركيبات داخل المنشأة {#on-premise}

بالنسبة لتثبيتات تويست داخل الشركة، ستحتاج إلى إنشاء تطبيق Slack الخاص بك وتهيئة
متغيرات البيئة اللازمة.

### إنشاء تطبيق Slack {#create-slack-app}

1. انتقل إلى صفحة [تطبيقات Slack API Apps] (https://api.slack.com/apps) وانقر
   **إنشاء تطبيق جديد**
2. اختر **من بيان التطبيق** وحدد مساحة العمل التي تريد تثبيت التطبيق فيها
3. الصق البيان التالي، مستبدلاً عنوان URL الخاص بإعادة التوجيه بعنوان URL الخاص
   بخادم تويست:

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. مراجعة التطبيق وإنشاء التطبيق

### تكوين متغيرات البيئة {#configure-environment}

قم بتعيين متغيرات البيئة التالية على خادم تويست الخاص بك:

- `SLACK_CLIENT_ID` - معرف العميل من صفحة المعلومات الأساسية لتطبيق Slack الخاص
  بك
- `SLACK_CLIENT_SECRET` - سر العميل من صفحة المعلومات الأساسية لتطبيق Slack
  الخاص بك
