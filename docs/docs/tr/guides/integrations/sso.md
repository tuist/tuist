---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Google Workspace organizasyonunuz varsa ve aynı Google barındırma alanıyla
oturum açan tüm geliştiricilerin Tuist organizasyonunuza eklenmesini
istiyorsanız, bunu şu şekilde ayarlayabilirsiniz:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
Ayarlamakta olduğunuz etki alanına bağlı kuruluşun e-posta adresini kullanarak
Google'da kimlik doğrulaması yapmanız gerekir.
<!-- -->
:::

## Okta {#okta}

Okta ile SSO yalnızca kurumsal müşteriler için kullanılabilir. Bu özelliği
kurmakla ilgileniyorsanız, lütfen [contact@tuist.dev](mailto:contact@tuist.dev)
adresinden bizimle iletişime geçin.

Süreç boyunca, Okta SSO'yu kurmanıza yardımcı olacak bir irtibat kişisi
atanacaktır.

Öncelikle, bir Okta uygulaması oluşturmanız ve Tuist ile çalışacak şekilde
yapılandırmanız gerekir:
1. Okta yönetici panosuna gidin
2. Uygulamalar > Uygulamalar > Uygulama Entegrasyonu Oluştur
3. "OIDC - OpenID Connect" ve "Web Uygulaması"nı seçin.
4. Uygulamanın görüntü adını girin, örneğin "Tuist". [Bu
   URL](https://tuist.dev/images/tuist_dashboard.png) adresinde bulunan Tuist
   logosunu yükleyin.
5. Şimdilik oturum açma yönlendirme URI'lerini olduğu gibi bırakın.
6. "Görevler" altında, SSO Uygulamasına istediğiniz erişim kontrolünü seçin ve
   kaydedin.
7. Kaydettikten sonra, uygulamanın genel ayarları kullanılabilir hale
   gelecektir. "Müşteri Kimliği" ve "Müşteri Gizli Anahtarı"nı kopyalayın –
   bunları irtibat kişinizle güvenli bir şekilde paylaşmanız gerekecektir.
8. Tuist ekibi, sağlanan istemci kimliği ve gizli anahtarı ile Tuist sunucusunu
   yeniden dağıtmalıdır. Bu işlem bir iş günü sürebilir.
9. Sunucu dağıtıldıktan sonra, Genel Ayarlar "Düzenle" düğmesine tıklayın.
10. Aşağıdaki yönlendirme URL'sini yapıştırın:
    `https://tuist.dev/users/auth/okta/callback`
13. "Giriş başlatıldı" ifadesini "Okta veya Uygulama" olarak değiştirin.
14. "Kullanıcılara uygulama simgesini göster" seçeneğini seçin.
15. "Giriş URL'sini başlat"ı
    `https://tuist.dev/users/auth/okta?organization_id=1` ile güncelleyin.
    `organization_id`, irtibat kişiniz tarafından sağlanacaktır.
16. "Kaydet"i tıklayın.
17. Okta kontrol panelinden Tuist oturum açma işlemini başlatın.
18. Aşağıdaki komutu çalıştırarak Okta etki alanından oturum açan kullanıcılara
    Tuist kuruluşunuza otomatik olarak erişim izni verin:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
Tuist şu anda Okta kuruluşunuzdaki kullanıcıların otomatik olarak sağlanmasını
ve kaldırılmasını desteklemediğinden, kullanıcıların önce Okta kontrol
panelinden oturum açmaları gerekir. Okta kontrol panelinden oturum açtıklarında,
Tuist kuruluşunuza otomatik olarak ekleneceklerdir.
<!-- -->
:::
