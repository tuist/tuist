---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# İçgörü toplayın {#gather-insights}

Tuist, yeteneklerini genişletmek için bir sunucu ile entegre olabilir. Bu
yeteneklerden biri de projeniz ve derlemeleriniz hakkında bilgi toplamaktır.
İhtiyacınız olan tek şey, sunucuda bir projeye sahip bir hesabınızın olmasıdır.

Her şeyden önce, çalıştırarak kimlik doğrulaması yapmanız gerekir:

```bash
tuist auth login
```

## Bir proje oluşturun {#create-a-project}

Daha sonra çalıştırarak bir proje oluşturabilirsiniz:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Projenin tam tanıtıcısını temsil eden `my-handle/MyApp` adresini kopyalayın.

## Projeleri bağlayın {#connect-projects}

Projeyi sunucuda oluşturduktan sonra, yerel projenize bağlamanız gerekecektir. `
tuist edit` adresini çalıştırın ve `Tuist.swift` dosyasını projenin tam
tanıtıcısını içerecek şekilde düzenleyin:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

İşte bu! Artık projeniz ve derlemeleriniz hakkında bilgi toplamaya hazırsınız.
Sonuçları sunucuya bildiren testleri çalıştırmak için `tuist test` adresini
çalıştırın.

> [!NOTE]
> Tuist sonuçları yerel olarak sıraya koyar ve komutu engellemeden göndermeye
> çalışır. Bu nedenle, komut bittikten hemen sonra gönderilmeyebilirler. CI'da
> sonuçlar hemen gönderilir.


![Sunucudaki çalıştırmaların listesini gösteren bir
görüntü](/images/guides/quick-start/runs.png)

Projelerinizden ve derlemelerinizden gelen verilere sahip olmak, bilinçli
kararlar almak için çok önemlidir. Tuist, yeteneklerini genişletmeye devam
edecek ve siz de proje yapılandırmanızı değiştirmek zorunda kalmadan bunlardan
yararlanacaksınız. Sihir, değil mi? 🪄
