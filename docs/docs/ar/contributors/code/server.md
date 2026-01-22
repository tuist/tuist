---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# الخادم {#server}

المصدر:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## ما الغرض منه {#what-it-is-for}

يوفر الخادم ميزات Tuist من جانب الخادم مثل المصادقة والحسابات والمشاريع وتخزين
ذاكرة التخزين المؤقتة والرؤى والمعاينات والتسجيل والتكاملات (GitHub و Slack و
SSO). وهو تطبيق Phoenix/Elixir مع Postgres و ClickHouse.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB أصبح قديمًا وسيتم إزالته. في الوقت الحالي، إذا كنت بحاجة إليه
للإعداد المحلي أو عمليات الترحيل، فاستخدم [وثائق تثبيت
TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/).
<!-- -->
:::

## كيفية المساهمة {#how-to-contribute}

تتطلب المساهمات في الخادم توقيع CLA (`server/CLA.md`).

### قم بالإعداد محليًا {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!ملاحظة] يقوم مطورو الطرف الأول بتحميل الأسرار المشفرة من
> `priv/secrets/dev.key`. لن يكون لدى المساهمين الخارجيين هذا المفتاح، ولا بأس
> بذلك. لا يزال الخادم يعمل محليًا مع `TUIST_SECRET_KEY_BASE` ، ولكن OAuth و
> Stripe والتكاملات الأخرى تظل معطلة.

### الاختبارات والتنسيق {#tests-and-formatting}

- الاختبارات: `اختبار المزج`
- التنسيق: `تنسيق mise run`
