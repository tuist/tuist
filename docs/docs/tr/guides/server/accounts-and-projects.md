---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Hesaplar ve projeler {#accounts-and-projects}

Bazı Tuist özellikleri, verilerin kalıcılığını artıran ve diğer hizmetlerle
etkileşime girebilen bir sunucu gerektirir. Sunucuyla etkileşim kurmak için,
yerel projenize bağlanacağınız bir hesap ve bir projeye ihtiyacınız vardır.

## Hesaplar {#accounts}

Sunucuyu kullanmak için bir hesaba ihtiyacınız vardır. İki tür hesap vardır:

- **Kişisel hesap:** Bu hesaplar, kaydolduğunuzda otomatik olarak oluşturulur ve
  kimlik sağlayıcısından (örneğin GitHub) veya e-posta adresinin ilk bölümünden
  elde edilen bir tanıtıcı ile tanımlanır.
- **Kuruluş hesabı:** Bu hesaplar manuel olarak oluşturulur ve geliştirici
  tarafından tanımlanan bir kullanıcı adı ile tanımlanır. Kuruluşlar, diğer
  üyeleri projelere işbirliği için davet etmeye izin verir.

[GitHub](https://github.com) ile aşina iseniz, bu kavram onlarınkine benzerdir;
burada kişisel ve kurumsal hesaplarınız olabilir ve bunlar URL'leri oluştururken
kullanılan *kullanıcı adı* ile tanımlanır.

::: info CLI-FIRST
<!-- -->
Hesapları ve projeleri yönetmek için yapılan işlemlerin çoğu CLI aracılığıyla
gerçekleştirilir. Hesapları ve projeleri yönetmeyi kolaylaştıracak bir web
arayüzü üzerinde çalışıyoruz.
<!-- -->
:::

Organizasyonu <LocalizedLink href="/cli/organization">`tuist
organization`</LocalizedLink> alt komutları aracılığıyla yönetebilirsiniz. Yeni
bir organizasyon hesabı oluşturmak için şunu çalıştırın:
```bash
tuist organization create {account-handle}
```

## Projeler {#projects}

Tuist veya ham Xcode projeleriniz, uzak bir proje aracılığıyla hesabınızla
entegre edilmelidir. GitHub ile karşılaştırmaya devam edecek olursak, bu,
değişikliklerinizi aktardığınız yerel ve uzak bir depoya sahip olmak gibidir.
<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> kullanarak
projeler oluşturabilir ve yönetebilirsiniz.

Projeler, kuruluş tanıtıcısı ile proje tanıtıcısının birleştirilmesiyle elde
edilen tam tanıtıcı ile tanımlanır. Örneğin, tanıtıcısı `tuist` olan bir
kuruluşunuz ve tanıtıcısı `tuist` olan bir projeniz varsa, tam tanıtıcı
`tuist/tuist` olur.

Yerel ve uzak proje arasındaki bağ, yapılandırma dosyası aracılığıyla yapılır.
Eğer yoksa, `Tuist.swift` adresinde oluşturun ve aşağıdaki içeriği ekleyin:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
<LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink> gibi
bazı özelliklerin Tuist projesine sahip olmanızı gerektirdiğini unutmayın. Ham
Xcode projeleri kullanıyorsanız, bu özellikleri kullanamazsınız.
<!-- -->
:::

Projenizin URL'si tam tanıtıcı kullanılarak oluşturulur. Örneğin, herkese açık
olan Tuist'in kontrol paneline
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) adresinden erişilebilir.
Burada `tuist/tuist` projenin tam tanıtıcısıdır.
