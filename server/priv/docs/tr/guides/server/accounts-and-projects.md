---
{
  "title": "Hesaplar ve projeler",
  "titleTemplate": ":title | Server | Kılavuzlar | Tuist",
  "description": "Tuist'te hesapların ve projelerin nasıl oluşturulacağını ve yönetileceğini öğrenin."
}
---
# Hesaplar ve projeler {#accounts-and-projects}

Bazı Tuist özellikleri, verilerin kalıcılığını sağlayan ve diğer hizmetlerle etkileşime girebilen bir sunucu gerektirir. Sunucuyla etkileşim kurmak için yerel projenize bağladığınız bir hesap ve bir projeye ihtiyacınız vardır.

## Hesaplar {#accounts}

Sunucuyu kullanmak için bir hesaba ihtiyacınız olacak. İki tür hesap bulunur:

- **Kişisel hesap:** Bu hesaplar kaydolduğunuzda otomatik olarak oluşturulur ve kimlik sağlayıcısından (örneğin GitHub) veya e-posta adresinin ilk bölümünden elde edilen bir tanıtıcı ile tanımlanır.
- **Organizasyon hesabı:** Bu hesaplar manuel olarak oluşturulur ve geliştirici tarafından tanımlanan bir tanıtıcı ile tanımlanır. Organizasyonlar, projelerde iş birliği yapmak üzere diğer üyeleri davet etmeye olanak tanır.

[GitHub](https://github.com) aşinalığınız varsa, kavram onlara benzer; kişisel ve organizasyon hesaplarına sahip olabilirsiniz ve bunlar URL’ler oluşturulurken kullanılan bir *tanıtıcı* ile tanımlanır.

Organizasyonu <.localized_link href="/cli/organization">`tuist organization`</.localized_link> altındaki alt komutlar aracılığıyla yönetebilirsiniz. Yeni bir organizasyon hesabı oluşturmak için şunu çalıştırın:
```bash
tuist organization create {account-handle}
```

### Organizasyon üyeliği {#organization-membership}

Kullanıcılar bir davetiye, otomatik tek oturum açma kaydı veya <.localized_link href="/guides/integrations/authentication/scim">Sistemler Arası Kimlik Yönetimi sağlama</.localized_link> yoluyla organizasyon üyesi olabilir.

Bir organizasyonun kimlik sağlayıcısıyla kimlik doğrulaması yapmak tek başına üyelik sağlamaz. Organizasyonun <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">tek oturum açma kayıt politikası</.localized_link>, güvenilir alanından gelen bir kullanıcının davetiyeye ihtiyaç duyup duymadığını veya otomatik olarak katılıp katılamayacağını belirler.

Yöneticiler panodan veya <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> ile bir üyeyi davet edebilir. Davetli kabul ettiğinde `user` dışında bir rol vermek için `--role admin` veya `--role viewer` parametrelerini iletin.

### Roller {#roles}

Her organizasyon üyesi üç rolden birine sahiptir:

| Rol | Sağladıkları |
| --- | --- |
| **Yönetici** | Bir kullanıcının yapabileceği her şey artı organizasyonu yönetme: üyeler ve davetiyeler, projeler, faturalandırma, token’lar, web kancaları ve ayarlar. |
| **Kullanıcı** | Organizasyonun işini okur ve üzerinde işlem yapar: derlemeleri ve testleri çalıştırma, önbelleğe yazma, ön izlemeler oluşturma ve silme ve bir test senaryosunun durumunu değiştirme. |
| **Görüntüleyici** | Organizasyonun işini okur ancak hiçbirini değiştirmez. Panolar, derlemeler, test çalıştırmaları, kararsız ve karantinaya alınmış testler, ön izlemeler, paketler ve çalıştırıcı etkinliği okunabilir durumdadır. Bir çalıştırıcıya interaktif kabuk veya VNC oturumu bağlamak mümkün değildir çünkü bu, makinede komutlar çalıştırır. |

Birini davet ederken bir rol seçin ve daha sonra panodaki **Üyeler** bölümünden değiştirin. Bu şekilde belirlenen bir rol, sonraki bir oturum açma işlemiyle asla üzerine yazılmaz.

## Projeler {#projects}

Projelerinizin hesabınızla entegre edilmesi için uzak bir proje gerekir. GitHub karşılaştırmasını sürdürürsek, değişikliklerinizi gönderdiğiniz yerel ve uzak bir depoya sahip olmak gibidir. Projeleri oluşturmak ve yönetmek için <.localized_link href="/cli/project">`tuist project`</.localized_link> kullanabilirsiniz.

Projeler, organizasyon tanıtıcısı ve proje tanıtıcısının birleştirilmesiyle oluşan tam tanıtıcı ile tanımlanır. Örneğin, `tuist` tanıtıcısına sahip bir organizasyonunuz ve `tuist` tanıtıcısına sahip bir projeniz varsa, tam tanıtıcı `tuist/tuist` olur.

Yerel ve uzak proje arasındaki bağlama yapılandırma dosyası aracılığıyla yapılır. Henüz yoksa, `Tuist.swift` konumunda oluşturun ve aşağıdaki içeriği ekleyin:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **Yalnızca Tuist projesine özel özellikler**
>
> <.localized_link href="/guides/features/cache/module-cache">modül önbellekleme</.localized_link> gibi bazı özelliklerin Tuist tarafından yönetilen bir proje gerektirdiğini unutmayın. Projenizi yönetmek için Tuist kullanmıyorsanız bu özellikleri kullanamazsınız.


Projenizin URL’si tam tanıtıcı kullanılarak oluşturulur. Örneğin, Tuist’in herkese açık olan panosu [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) adresinden erişilebilir; burada `tuist/tuist` projenin tam tanıtıcısıdır.
