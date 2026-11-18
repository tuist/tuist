---
{
  "title": "Önizlemeleri CLI ile çalıştırın",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Mobil uygulamaları, macOS uygulamalarını ve komut satırı önizlemelerini Tuist CLI ile çalıştırın."
}
---
# Önizlemeleri CLI ile çalıştırın

<.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> öğesini kurun, ardından paylaşılan bir önizleme bağlantısını çalıştırın. Önizlemeyi oluşturan derleme sistemine ihtiyacınız yoktur:

```bash
tuist run {url}
```

Tuist; işletim sisteminiz, CPU mimariniz ve hedefiniz için uyumlu bir derleme seçer. Özel önizlemeler kimlik doğrulama ve proje erişimi gerektirir.

## Mobil uygulamalar {#mobile-applications}

Bağlı bir cihaz veya simülatör seçin:

```bash
tuist run --device "My device" {url}
```

Android cihazlar ve emülatörler ADB üzerinden bağlı olmalıdır. APK'yı önizleme sayfasından indirip, bu kaynaktan yüklemeye izin veren bir Android cihaza kurabilirsiniz. Apple derlemeleri hedef platformla eşleşmeli ve imzalama gereksinimlerini karşılamalıdır. Bir IPA için, onu kurmak üzere önizleme bağlantısını hedef cihazda açın.

## Komut satırı önizlemeleri {#command-line-previews}

Argümanları `--` sonrasına iletin:

```bash
tuist run {url} -- --help
tuist run {url} -- build --configuration Release
```

`--` sonrasındaki her şey olduğu gibi iletilir; buna `--verbose`, `--quiet` ve `--path` dahildir. Alt argümanlar Tuist komut analizlerine dahil edilmez.

Önizleme; çalışma dizininiz, ortamınız ve terminal giriş/çıkışınızla çalışır ve yürütülebilir dosyanın çıkış durumunu döndürür. Kurulu bir CLI'nin yerine geçmez veya onu `PATH` yoluna eklemez. CLI dağıtımları, oluşturulan projelerin bunlara referans vermeye devam edebilmesi için yürütmeden sonra Tuist'in yerel `previews` önbelleğinde kalır; bu önbelleğin silinmesi söz konusu referansların hedeflerini de kaldırır.

Masaüstü ve CLI önizlemeleri korumalı alan yerine geçerli kullanıcı olarak çalışır. Yalnızca güvendiğiniz yazarlardan ve çekme isteklerinden gelen derlemeleri çalıştırın.

## Bir sürüm seçin {#select-a-version}

`tuist run` ayrıca `latest` içeren bir uygulama adı, bir dal adı veya bir commit karması kabul eder:

```bash
tuist run App@latest # Latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Latest App preview associated with a branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Preview associated with a commit
```

Bu seçiciler, ilgili Git meta verilerinin yayımlanmış olmasını gerektirir. Git meta verilerini atlayan iş akışları için bunun yerine belirli önizleme URL'sini kullanın.

Erişim ve organizasyon için bkz. <.localized_link href="/guides/features/previews#visibility">görünürlük ve izler</.localized_link>.
