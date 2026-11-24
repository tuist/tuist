---
{
  "title": "Hesaplar ve projeler",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist'te hesapların ve projelerin nasıl oluşturulup yönetileceğini öğrenin."
}
---
# Hesaplar ve projeler {#accounts-and-projects}

Bazı Tuist özellikleri, veri kalıcılığı sağlayan ve diğer hizmetlerle etkileşime geçebilen bir sunucu gerektirir. Sunucuyla etkileşim kurmak için yerel projenize bağlayacağınız bir hesap ve bir projeye ihtiyacınız vardır.

## Hesaplar {#accounts}

Sunucuyu kullanmak için bir hesaba ihtiyacınız olacaktır. İki tür hesap bulunur:

- **Kişisel hesap:** Bu hesaplar kaydolduğunuzda otomatik olarak oluşturulur ve kimlik sağlayıcısından (örneğin GitHub) veya e-posta adresinin ilk bölümünden alınan bir tanıtıcı ile tanımlanır.
- **Organizasyon hesabı:** Bu hesaplar manuel olarak oluşturulur ve geliştirici tarafından belirlenen bir tanıtıcı ile tanımlanır. Organizasyonlar, projelerde iş birliği yapmak üzere diğer üyeleri davet etmeye olanak tanır.

[GitHub](https://github.com) aşinaysanız kavram benzerdir: kişisel ve organizasyon hesaplarınız olabilir ve bunlar URL’ler oluşturulurken kullanılan bir *tanıtıcı* ile tanımlanır.

Organizasyonu <.localized_link href="/cli/organization">`tuist organization`</.localized_link> altındaki alt komutlar aracılığıyla yönetebilirsiniz. Yeni bir organizasyon hesabı oluşturmak için şunu çalıştırın:
```bash
tuist organization create {account-handle}
```

### Organizasyon üyeliği {#organization-membership}

Kullanıcılar davet, otomatik tek oturum açma kaydı veya <.localized_link href="/guides/integrations/authentication/scim">Sistem for Cross-domain Identity Management provisioning</.localized_link> yoluyla organizasyon üyesi olabilir.

Bir organizasyonun kimlik sağlayıcısıyla kimlik doğrulaması yapmak tek başına üyelik sağlamaz. Organizasyonun <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma kayıt politikası</.localized_link>, güvenilir alanından gelen bir kullanıcının davete mi ihtiyacı olduğunu yoksa otomatik olarak katılabileceğini belirler.

Yöneticiler panodan veya <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> ile bir üye davet edebilir. Kabul ettiklerinde davet edilen kişiye `user` dışında bir rol atamak için `--role admin` veya `--role viewer` parametrelerini iletin.

### Roller {#roles}

Her organizasyon üyesi üç rolden birine sahiptir:

| Rol | Sağladıkları |
| --- | --- |
| **Yönetici** | Bir kullanıcının yapabileceği her şeyin yanı sıra organizasyonu yönetme: üyeler ve davetler, projeler, faturalandırma, token’lar, webhook’lar ve ayarlar. |
| **Kullanıcı** | Organizasyonun çalışmalarını okur ve üzerinde işlem yapar: derlemeleri ve testleri çalıştırma, önbelleğe yazma, önizlemeler oluşturma ve silme ve bir test senaryosunun durumunu değiştirme. |
| **Görüntüleyici** | Organizasyonun çalışmalarını okur ancak hiçbirini değiştirmez. Panolar, derlemeler, test çalıştırmaları, kararsız ve karantinaya alınmış testler, önizlemeler, paketler ve runner etkinliği okunabilir durumdadır. Bir makinede komut çalıştırdığı için bir runner’a etkileşimli kabuk veya VNC oturumu bağlamak bu kapsamda değildir. |

Birini davet ederken bir rol seçin ve daha sonra panoda **Üyeler** bölümünden değiştirin. Bu şekilde atanmış bir rol, sonraki oturum açmalarda asla üzerine yazılmaz.

## Projeler {#projects}

Projelerinizin uzaktan bir proje aracılığıyla hesabınızla entegre edilmesi gerekir. GitHub karşılaştırmasını sürdürürsek, değişikliklerinizi gönderdiğiniz yerel ve uzak bir deponuzun olması gibidir. Projeleri oluşturmak ve yönetmek için <.localized_link href="/cli/project">`tuist project`</.localized_link> kullanabilirsiniz.

Projeler, organizasyon tanıtıcısı ile proje tanıtıcısının birleştirilmesiyle oluşan tam tanıtıcı ile tanımlanır. Örneğin, `tuist` tanıtıcısına sahip bir organizasyonunuz ve `tuist` tanıtıcısına sahip bir projeniz varsa tam tanıtıcı `tuist/tuist` olur.

Yerel ve uzak proje arasındaki bağlama yapılandırma dosyası üzerinden yapılır. Böyle bir dosyanız yoksa `Tuist.swift` konumunda oluşturun ve aşağıdaki içeriği ekleyin:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Yalnızca Tuist projesine özgü özellikler**
>
> <.localized_link href="/guides/features/cache/module-cache">modül önbellekleme</.localized_link> gibi bazı özelliklerin Tuist tarafından yönetilen bir proje gerektirdiğini unutmayın. Projenizi yönetmek için Tuist kullanmıyorsanız bu özelliklerden yararlanamazsınız.


Projenizin URL’si tam tanıtıcı kullanılarak oluşturulur. Örneğin, herkese açık olan Tuist panosu [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) adresinden erişilebilir; burada `tuist/tuist` projenin tam tanıtıcısıdır.
