---
{
  "title": "Hesaplar ve projeler",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist'te hesapları ve projeleri nasıl oluşturup yöneteceğinizi öğrenin."
}
---
# Hesaplar ve projeler {#accounts-and-projects}

Bazı Tuist özellikleri, verilerin kalıcılığını sağlayan ve diğer hizmetlerle etkileşime girebilen bir sunucu gerektirir. Sunucuyla etkileşim kurmak için yerel projenize bağladığınız bir hesap ve bir projeye ihtiyacınız vardır.

## Hesaplar {#accounts}

Sunucuyu kullanmak için bir hesaba ihtiyacınız olacaktır. İki tür hesap bulunur:

- **Kişisel hesap:** Bu hesaplar kaydolduğunuzda otomatik olarak oluşturulur ve kimlik sağlayıcısından (örneğin GitHub) veya e-posta adresinin ilk kısmından alınan bir tanıtıcı ile tanımlanır.
- **Organizasyon hesabı:** Bu hesaplar manuel olarak oluşturulur ve geliştirici tarafından tanımlanan bir tanıtıcı ile tanımlanır. Organizasyonlar, projelerde işbirliği yapmak üzere diğer üyelerin davet edilmesine olanak tanır.

[GitHub](https://github.com) ile aşinaysanız kavram benzerdir; kişisel ve organizasyon hesaplarınız olabilir ve bunlar URL'ler oluşturulurken kullanılan bir *tanıtıcı* ile tanımlanır.

Organizasyonu <.localized_link href="/cli/organization">`tuist organization`</.localized_link> altındaki alt komutlar aracılığıyla yönetebilirsiniz. Yeni bir organizasyon hesabı oluşturmak için şunu çalıştırın:
```bash
tuist organization create {account-handle}
```

### Organizasyon üyeliği {#organization-membership}

Kullanıcılar bir davet, otomatik tek oturum açma kaydı veya <.localized_link href="/guides/integrations/authentication/scim">Çapraz Alan Kimlik Yönetimi sistemi sağlama</.localized_link> yoluyla organizasyon üyesi olabilir.

Bir organizasyonun kimlik sağlayıcısıyla kimlik doğrulaması yapmak tek başına üyelik sağlamaz. Organizasyonun <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma kayıt politikası</.localized_link>, güvenilir alanından gelen bir kullanıcının davete mi ihtiyacı olduğunu yoksa otomatik olarak katılmasına mı izin verildiğini belirler.

Yöneticiler panodan veya <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> ile bir üye davet edebilir. Davetli kabul ettiğinde `user` dışında bir rol vermek için `--role admin` veya `--role viewer` parametrelerini geçirin.

### Roller {#roles}

Her organizasyon üyesi üç rolden birine sahiptir:

| Rol | Sağladıkları |
| --- | --- |
| **Yönetici** | Bir kullanıcının yapabileceği her şey artı organizasyonu yönetme: üyeler ve davetler, projeler, faturalandırma, token'lar, webhook'lar ve ayarlar. |
| **Kullanıcı** | Organizasyonun işini okur ve üzerinde işlem yapar: derlemeleri ve testleri çalıştırma, önbelleğe yazma, önizlemeler oluşturma ve silme ve bir test senaryosunun durumunu değiştirme. |
| **Görüntüleyici** | Organizasyonun işini okur ancak hiçbirini değiştirmez. Panolar, derlemeler, test çalıştırmaları, kararsız ve karantinaya alınmış testler, önizlemeler, paketler ve çalıştırıcı etkinliği okunabilir durumdadır. Makinede komut çalıştırdığı için bir çalıştırıcıya etkileşimli kabuk veya VNC oturumu bağlamak mümkün değildir. |

Birini davet ederken bir rol seçin ve daha sonra panodaki **Üyeler** bölümünden değiştirin. Bu şekilde ayarlanan bir rol, sonraki bir oturum açma işlemiyle asla üzerine yazılmaz.

## Projeler {#projects}

Projelerinizin uzaktan bir proje aracılığıyla hesabınızla entegre edilmesi gerekir. GitHub karşılaştırmasına devam edersek, değişikliklerinizi gönderdiğiniz yerel ve uzak bir deponuz olması gibidir. Projeleri oluşturmak ve yönetmek için <.localized_link href="/cli/project">`tuist project`</.localized_link> kullanabilirsiniz.

Projeler, organizasyon tanıtıcısı ve proje tanıtıcısının birleştirilmesiyle elde edilen tam bir tanıtıcı ile tanımlanır. Örneğin, `tuist` tanıtıcısına sahip bir organizasyonunuz ve `tuist` tanıtıcısına sahip bir projeniz varsa tam tanıtıcı `tuist/tuist` olur.

Yerel ve uzak proje arasındaki bağlama yapılandırma dosyası aracılığıyla yapılır. Böyle bir dosyanız yoksa `Tuist.swift` konumunda oluşturun ve aşağıdaki içeriği ekleyin:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Yalnızca Tuist projesine özgü özellikler**
>
> <.localized_link href="/guides/features/cache/module-cache">Modül önbellekleme</.localized_link> gibi bazı özelliklerin Tuist tarafından yönetilen bir proje gerektirdiğini unutmayın. Projenizi yönetmek için Tuist kullanmıyorsanız bu özellikleri kullanamazsınız.


Projenizin URL'si tam tanıtıcı kullanılarak oluşturulur. Örneğin, herkese açık olan Tuist panosu [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) adresinden erişilebilir; burada `tuist/tuist` projenin tam tanıtıcısıdır.
