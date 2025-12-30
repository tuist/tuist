---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Hesaplar ve projeler {#accounts-and-projects}

Bazı Tuist özellikleri, verilerin kalıcılığını sağlayan ve diğer hizmetlerle
etkileşime girebilen bir sunucu gerektirir. Sunucu ile etkileşime geçmek için
bir hesaba ve yerel projenize bağladığınız bir projeye ihtiyacınız vardır.

## Hesaplar {#accounts}

Sunucuyu kullanmak için bir hesaba ihtiyacınız olacak. İki tür hesap vardır:

- **Kişisel hesap:** Bu hesaplar, kaydolduğunuzda otomatik olarak oluşturulur ve
  kimlik sağlayıcısından (örneğin GitHub) veya e-posta adresinin ilk bölümünden
  elde edilen bir tanıtıcı ile tanımlanır.
- **Organizasyon hesabı:** Bu hesaplar manuel olarak oluşturulur ve geliştirici
  tarafından tanımlanan bir tanıtıcı ile tanımlanır. Organizasyonlar, diğer
  üyelerin projeler üzerinde işbirliği yapmaya davet edilmesine izin verir.

GitHub](https://github.com)'a aşinaysanız, konsept onlarınkine benzer; kişisel
ve kurumsal hesaplarınız olabilir ve bunlar URL'ler oluşturulurken kullanılan
bir *tanıtıcısı* ile tanımlanır.

::: info CLI-FIRST
<!-- -->
Hesapları ve projeleri yönetmek için çoğu işlem CLI aracılığıyla yapılır.
Hesapları ve projeleri yönetmeyi kolaylaştıracak bir web arayüzü üzerinde
çalışıyoruz.
<!-- -->
:::

Organizasyonu <LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink> altındaki alt komutlar aracılığıyla
yönetebilirsiniz. Yeni bir organizasyon hesabı oluşturmak için çalıştırın:
```bash
tuist organization create {account-handle}
```

## Projeler {#projects}

Projelerinizin, ister Tuist'in ister ham Xcode'un olsun, uzak bir proje
aracılığıyla hesabınızla entegre edilmesi gerekir. GitHub ile karşılaştırmaya
devam edersek, değişikliklerinizi gönderdiğiniz bir yerel ve bir uzak depoya
sahip olmak gibidir. Projeleri oluşturmak ve yönetmek için
<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> adresini
kullanabilirsiniz.

Projeler, kuruluş tanıtıcısı ve proje tanıtıcısının birleştirilmesinin sonucu
olan tam tanıtıcı ile tanımlanır. Örneğin, `tuist` tanıtıcısına sahip bir
kuruluşunuz ve `tuist` tanıtıcısına sahip bir projeniz varsa, tam tanıtıcı
`tuist/tuist` olacaktır.

Yerel ve uzak proje arasındaki bağlama, yapılandırma dosyası aracılığıyla
yapılır. Eğer yoksa, `Tuist.swift` adresinde oluşturun ve aşağıdaki içeriği
ekleyin:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
Tuist projesine sahip olmanızı gerektiren
<LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink> gibi
bazı özellikler olduğunu unutmayın. Ham Xcode projeleri kullanıyorsanız, bu
özellikleri kullanamazsınız.
<!-- -->
:::

Projenizin URL'si tam tanıtıcı kullanılarak oluşturulur. Örneğin, Tuist'in
herkese açık olan kontrol paneline
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) adresinden erişilebilir;
burada `tuist/tuist` projenin tam tanıtıcısıdır.
