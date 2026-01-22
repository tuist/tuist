---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Если у вас есть организация Google Workspace и вы хотите, чтобы любой
разработчик, который входит в систему с того же домена, хостируемого Google,
добавлялся в вашу организацию Tuist, вы можете настроить это с помощью:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
Вы должны пройти аутентификацию в Google, используя адрес электронной почты,
привязанный к организации, домен которой вы настраиваете.
<!-- -->
:::

## Okta {#okta}

SSO с Okta доступен только для корпоративных клиентов. Если вы заинтересованы в
его настройке, свяжитесь с нами по адресу
[contact@tuist.dev](mailto:contact@tuist.dev).

В ходе этого процесса вам будет назначен контактное лицо, которое поможет вам
настроить Okta SSO.

Сначала вам нужно создать приложение Okta и настроить его для работы с Tuist:
1. Перейти к панели администратора Okta
2. Приложения > Приложения > Создать интеграцию приложения
3. Выберите «OIDC — OpenID Connect» и «Веб-приложение».
4. Введите отображаемое название приложения, например «Tuist». Загрузите логотип
   Tuist, расположенный по адресу [этот
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. Пока что оставьте URI перенаправления для входа без изменений.
6. В разделе «Задания» выберите желаемый контроль доступа к приложению SSO и
   сохраните.
7. After saving, the general settings for the application will be available.
   Copy the "Client ID" and "Client Secret". Also note your Okta organization
   URL (e.g., `https://your-company.okta.com`) – you will need to safely share
   all of these with your point of contact.
8. Once the Tuist team has configured the SSO, click on General Settings "Edit"
   button.
9. Вставьте следующий URL-адрес перенаправления:
   `https://tuist.dev/users/auth/okta/callback`
10. Измените «Вход инициирован» на «Okta или приложение».
11. Выберите «Отображать значок приложения пользователям».
12. Обновите «URL для инициирования входа» на
    `https://tuist.dev/users/auth/okta?organization_id=1`. `organization_id`
    будет предоставлен вашим контактным лицом.
13. Нажмите «Сохранить».
14. Запустите вход в Tuist из панели управления Okta.

::: warning
<!-- -->
Пользователи должны сначала войти в систему через панель управления Okta, так
как Tuist в настоящее время не поддерживает автоматическую регистрацию и
удаление пользователей из вашей организации Okta. После входа в систему через
панель управления Okta они будут автоматически добавлены в вашу организацию
Tuist.
<!-- -->
:::
