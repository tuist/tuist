---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## جوجل {#google}

إذا كان لديك مؤسسة Google Workspace وتريد إضافة أي مطور يسجل الدخول بنفس المجال
المستضاف من Google إلى مؤسسة Tuist الخاصة بك، فيمكنك إعداد ذلك باستخدام:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

:::: تحذير
<!-- -->
يجب أن تكون مصادقًا مع Google باستخدام بريد إلكتروني مرتبط بالمؤسسة التي تقوم
بإعداد نطاقها.
<!-- -->
:::

## Okta {#okta}

SSO مع Okta متاح فقط للعملاء من الشركات. إذا كنت مهتمًا بإعداده، يرجى الاتصال
بنا على [contact@tuist.dev](mailto:contact@tuist.dev).

أثناء العملية، سيتم تعيين جهة اتصال لمساعدتك في إعداد Okta SSO.

أولاً، ستحتاج إلى إنشاء تطبيق Okta وتهيئته للعمل مع Tuist:
1. انتقل إلى لوحة تحكم Okta الإدارية
2. التطبيقات > التطبيقات > إنشاء تكامل التطبيقات
3. حدد "OIDC - OpenID Connect" و "تطبيق الويب"
4. أدخل اسم العرض للتطبيق، على سبيل المثال، "Tuist". قم بتحميل شعار Tuist
   الموجود في [هذا الرابط](https://tuist.dev/images/tuist_dashboard.png).
5. اترك عناوين URIs إعادة توجيه تسجيل الدخول كما هي في الوقت الحالي
6. تحت "المهام"، اختر التحكم في الوصول المطلوب إلى تطبيق SSO واحفظه.
7. After saving, the general settings for the application will be available.
   Copy the "Client ID" and "Client Secret". Also note your Okta organization
   URL (e.g., `https://your-company.okta.com`) – you will need to safely share
   all of these with your point of contact.
8. Once the Tuist team has configured the SSO, click on General Settings "Edit"
   button.
9. الصق عنوان URL التالي لإعادة التوجيه:
   `https://tuist.dev/users/auth/okta/callback`
10. قم بتغيير "Login initiated by" إلى "Either Okta or App".
11. حدد "عرض رمز التطبيق للمستخدمين"
12. قم بتحديث "عنوان URL لبدء تسجيل الدخول" بـ
    `https://tuist.dev/users/auth/okta?organization_id=1`. سيتم توفير
    `organization_id` من قبل جهة الاتصال الخاصة بك.
13. انقر على "حفظ".
14. ابدأ تسجيل الدخول إلى Tuist من لوحة تحكم Okta.

:::: تحذير
<!-- -->
يجب على المستخدمين تسجيل الدخول أولاً عبر لوحة تحكم Okta الخاصة بهم، حيث لا يدعم
Tuist حاليًا التزويد التلقائي وإلغاء التزويد التلقائي للمستخدمين من مؤسسة Okta
الخاصة بك. بمجرد تسجيل الدخول عبر لوحة تحكم Okta الخاصة بهم، سيتم إضافتهم
تلقائيًا إلى مؤسسة Tuist الخاصة بك.
<!-- -->
:::
