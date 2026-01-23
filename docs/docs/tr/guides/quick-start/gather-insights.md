---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# İçgörüler toplayın {#gather-insights}

Tuist, yeteneklerini genişletmek için bir sunucu ile entegre edilebilir. Bu
yeteneklerden biri, projeniz ve derlemeleriniz hakkında bilgi toplamaktır. Tek
ihtiyacınız olan, sunucuda bir projeye sahip bir hesap açmaktır.

Öncelikle, aşağıdaki komutu çalıştırarak kimlik doğrulaması yapmanız gerekir:

```bash
tuist auth login
```

## Proje oluşturun {#create-a-project}

Ardından şu komutu çalıştırarak bir proje oluşturabilirsiniz:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

`my-handle/MyApp` adresini kopyalayın. Bu adres, projenin tam tanıtıcısını
temsil eder.

## Projeleri bağlayın {#connect-projects}

Sunucuda projeyi oluşturduktan sonra, onu yerel projenize bağlamanız gerekir.
`tuist edit` komutunu çalıştırın ve `Tuist.swift` dosyasını düzenleyerek
projenin tam adresini ekleyin:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Voilà! Artık projeniz ve derlemeleriniz hakkında bilgi toplamaya hazırsınız.
`tuist test` komutunu çalıştırarak testleri çalıştırın ve sonuçları sunucuya
bildirin.

::: info
<!-- -->
Tuist, sonuçları yerel olarak sıraya alır ve komutu engellemeden göndermeye
çalışır. Bu nedenle, komut bittikten hemen sonra gönderilmeyebilirler. CI'da
sonuçlar hemen gönderilir.
<!-- -->
:::


![Sunucudaki çalıştırma listesini gösteren bir
resim](/images/guides/quick-start/runs.png)

Projelerinizden ve derlemelerinizden elde edilen veriler, bilinçli kararlar
almak için çok önemlidir. Tuist, yeteneklerini genişletmeye devam edecek ve siz
de proje yapılandırmanızı değiştirmenize gerek kalmadan bu yeteneklerden
yararlanabileceksiniz. Sihir gibi, değil mi? 🪄
