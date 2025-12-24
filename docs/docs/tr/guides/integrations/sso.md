---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Bir Google Workspace organizasyonunuz varsa ve aynı Google barındırılan alan
adıyla oturum açan herhangi bir geliştiricinin Tuist organizasyonunuza
eklenmesini istiyorsanız, bunu şu şekilde ayarlayabilirsiniz:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
Etki alanını ayarladığınız kuruluşa bağlı bir e-posta kullanarak Google'da
kimliğinizin doğrulanmış olması gerekir.
<!-- -->
:::

## Okta {#okta}

Okta ile SSO yalnızca kurumsal müşteriler için kullanılabilir. Bunu kurmakla
ilgileniyorsanız, lütfen [contact@tuist.dev](mailto:contact@tuist.dev)
adresinden bizimle iletişime geçin.

Süreç sırasında, Okta SSO'yu kurmanıza yardımcı olacak bir irtibat noktası
atanacaktır.

Öncelikle, bir Okta uygulaması oluşturmanız ve Tuist ile çalışacak şekilde
yapılandırmanız gerekecektir:
1. Okta yönetici kontrol paneline gidin
2. Uygulamalar > Uygulamalar > Uygulama Entegrasyonu Oluştur
3. "OIDC - OpenID Connect" ve "Web Uygulaması "nı seçin
4. Uygulama için görünen adı girin, örneğin "Tuist". Bu
   URL](https://tuist.dev/images/tuist_dashboard.png) adresinde bulunan Tuist
   logosunu yükleyin.
5. Oturum açma yönlendirme URI'larını şimdilik olduğu gibi bırakın
6. "Atamalar" altında SSO Uygulamasına istediğiniz erişim kontrolünü seçin ve
   kaydedin.
7. Kaydettikten sonra, uygulama için genel ayarlar mevcut olacaktır. "Müşteri
   Kimliğini" ve "Müşteri Sırrını" kopyalayın - bunu iletişim noktanızla güvenli
   bir şekilde paylaşmanız gerekecektir.
8. Tuist ekibinin, sağlanan istemci kimliği ve sırrı ile Tuist sunucusunu
   yeniden dağıtması gerekecektir. Bu işlem bir iş gününe kadar sürebilir.
9. Sunucu dağıtıldıktan sonra, Genel Ayarlar "Düzenle" düğmesine tıklayın.
10. Aşağıdaki yönlendirme URL'sini yapıştırın:
    `https://tuist.dev/users/auth/okta/callback`
13. "Login initiated by" ifadesini "Either Okta or App" olarak değiştirin.
14. "Kullanıcılara uygulama simgesini göster" öğesini seçin
15. "Oturum açma URL'sini" `https://tuist.dev/users/auth/okta?organization_id=1`
    ile güncelleyin. ` organization_id` iletişim noktanız tarafından
    sağlanacaktır.
16. "Kaydet "e tıklayın.
17. Okta kontrol panelinizden Tuist oturum açma işlemini başlatın.
18. Aşağıdaki komutu çalıştırarak Okta etki alanınızdan imzalanan kullanıcılara
    Tuist organizasyonunuza otomatik erişim verin:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
Tuist şu anda Okta organizasyonunuzdan kullanıcıların otomatik olarak
sağlanmasını ve kaldırılmasını desteklemediğinden, kullanıcıların başlangıçta
Okta kontrol panelleri aracılığıyla oturum açmaları gerekir. Okta panosu
üzerinden oturum açtıklarında, Tuist organizasyonunuza otomatik olarak
ekleneceklerdir.
<!-- -->
:::
