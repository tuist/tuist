---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# بروتوكول السياق النموذجي (MCP)

[بروتوكول سياق النموذج (MCP)] (https://www.claudemcp.com) هو معيار اقترحه [كلود]
(https://claude.ai) لتفاعل الآلات ذات السقف المنخفض مع بيئات التطوير. يمكنك
التفكير فيه على أنه USB-C الخاص بـ LLMs. مثل حاويات الشحن، التي جعلت الشحن
والنقل أكثر قابلية للتشغيل البيني، أو بروتوكولات مثل TCP، التي فصلت طبقة التطبيق
عن طبقة النقل، يجعل MCP التطبيقات التي تعمل بنظام LLM مثل
[Claude](https://claude.ai/) و [Claude
Code](https://docs.anthropic.com/en/docs/claude-code) والمحررين مثل
[Zed](https://zed.dev) و [Cursor](https://www.cursor.com) و [VS
Code](https://code.visualstudio.com) قابلة للتشغيل البيني مع المجالات الأخرى.

يوفر Tuist خادمًا محليًا من خلال CLI الخاص به حتى تتمكن من التفاعل مع بيئة تطوير
تطبيقاتك **** . من خلال ربط تطبيقات العميل الخاصة بك به، يمكنك استخدام اللغة
للتفاعل مع مشاريعك.

ستتعرف في هذه الصفحة على كيفية إعداده وإمكانياته.

:::: المعلومات
<!-- -->
يستخدم خادم تويست MCP أحدث مشاريع Xcode كمصدر للحقيقة للمشاريع التي تريد التفاعل
معها.
<!-- -->
:::

## قم بإعداده

يوفر Tuist أوامر الإعداد التلقائي للعملاء المشهورين المتوافقين مع MCP. ما عليك
سوى تشغيل الأمر المناسب لعميلك:

### [كلود] (https://claude.ai)

بالنسبة لـ [كلود سطح المكتب] (https://claude.ai/download)، قم بتشغيل:
```bash
tuist mcp setup claude
```

سيؤدي هذا إلى تكوين الملف في `~ ~/مكتبة/دعم
التطبيقات/كلود/كلود_desktop_config.json`.

### [كلود كود] (https://docs.anthropic.com/en/docs/claude-code)

بالنسبة لرمز كلود كود، قم بتشغيل:
```bash
tuist mcp setup claude-code
```

سيؤدي ذلك إلى تكوين نفس ملف كلود لسطح المكتب.

### [المؤشر] (https://www.cursor.com)

بالنسبة إلى Cursor IDE، يمكنك تكوينه عالميًا أو محليًا:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [زيد] (https://zed.dev)

بالنسبة لمحرر Zed، يمكنك أيضًا تكوينه عالميًا أو محليًا:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [رمز VS] (https://code.visualstudio.com)

بالنسبة لرمز VS Code مع امتداد MCP، قم بتكوينه عالميًا أو محليًا:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### التكوين اليدوي

إذا كنت تفضل التهيئة يدويًا أو كنت تستخدم عميل MCP مختلف، أضف خادم Tuist MCP إلى
تهيئة العميل:

:::: مجموعة الرموز

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## الإمكانيات

ستتعرف في الأقسام التالية على إمكانيات خادم تويست MCP.

### الموارد

#### أحدث المشاريع ومساحات العمل

يحتفظ تويست بسجل لمشاريع Xcode ومساحات العمل التي عملت عليها مؤخرًا، مما يتيح
لتطبيقك الوصول إلى الرسوم البيانية للتبعية الخاصة بها للحصول على رؤى قوية. يمكنك
الاستعلام عن هذه البيانات للكشف عن تفاصيل حول بنية مشروعك وعلاقاته، مثل:

- ما هي التبعيات المباشرة والمتعدية لهدف معين؟
- ما هو الهدف الذي يحتوي على أكبر عدد من الملفات المصدر، وكم عدد الملفات التي
  يتضمنها؟
- ما هي جميع المنتجات الثابتة (مثل المكتبات الثابتة أو الأطر الثابتة) في الرسم
  البياني؟
- هل يمكنك سرد جميع الأهداف، مرتبة أبجديًا، مع ذكر أسمائها وأنواع المنتجات (على
  سبيل المثال، تطبيق، إطار عمل، اختبار وحدة)؟
- ما هي الأهداف التي تعتمد على إطار عمل معين أو تبعية خارجية معينة؟
- ما هو إجمالي عدد الملفات المصدر في جميع الأهداف في المشروع؟
- هل توجد أي تبعيات دائرية بين الأهداف، وإذا كان الأمر كذلك، فأين؟
- ما هي الأهداف التي تستخدم مورداً محدداً (مثل صورة أو ملف plist)؟
- ما هي أعمق سلسلة تبعية في الرسم البياني، وما هي الأهداف المتضمنة؟
- هل يمكنك أن تريني جميع أهداف الاختبار وأهداف التطبيق أو إطار العمل المرتبطة
  بها؟
- ما هي الأهداف التي لديها أطول أوقات بناء بناءً على التفاعلات الأخيرة؟
- ما هي الاختلافات في التبعيات بين هدفين محددين؟
- هل هناك أي ملفات مصدر أو موارد غير مستخدمة في المشروع؟
- ما هي الأهداف التي تشترك في التبعيات المشتركة، وما هي هذه التبعيات؟

مع Tuist، يمكنك التعمق في مشاريع Xcode الخاصة بك كما لم يحدث من قبل، مما يسهل
عليك فهم وتحسين وإدارة حتى أكثر الإعدادات تعقيدًا!
