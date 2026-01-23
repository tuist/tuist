---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Paket içgörüler {#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
<!-- -->
:::

Uygulamanıza daha fazla özellik ekledikçe, uygulama paketinizin boyutu da artar.
Daha fazla kod ve varlık gönderdiğinizde paket boyutunun artması kaçınılmaz olsa
da, varlıklarınızın paketlerinizde yinelenmediğinden emin olmak veya
kullanılmayan ikili sembolleri kaldırmak gibi bu artışı en aza indirmenin birçok
yolu vardır. Tuist, uygulama boyutunuzun küçük kalmasına yardımcı olacak araçlar
ve bilgiler sunar. Ayrıca, uygulama boyutunuzu zaman içinde izleriz.

## Kullanım {#usage}

Bir paketi analiz etmek için `tuist inspect bundle` komutunu kullanabilirsiniz:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

`tuist inspect bundle` komutu, paketi analiz eder ve paketin içeriğinin
taranması veya modül dökümü dahil olmak üzere paketin ayrıntılı bir özetini
görmek için bir bağlantı sağlar:

![Analiz edilen paket](/images/guides/features/bundle-size/analyzed-bundle.png)

## Sürekli entegrasyon {#continuous-integration}

Zaman içinde paket boyutunu takip etmek için, CI'da paketi analiz etmeniz
gerekir. Öncelikle, CI'nızın
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">kimlik
doğrulamasının yapıldığından</LocalizedLink> emin olmanız gerekir:

GitHub Eylemleri için örnek bir iş akışı şu şekilde olabilir:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

Ayarları yaptıktan sonra, paket boyutunuzun zaman içinde nasıl değiştiğini
görebilirsiniz:

![Paket boyutu
grafiği](/images/guides/features/bundle-size/bundle-size-graph.png)

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git
platformuyla</LocalizedLink> entegre edin.
<!-- -->
:::

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla
bağlandığında, `tuist inspect bundle` komutunu her çalıştırdığınızda Tuist,
pull/merge isteklerinize doğrudan bir yorum ekleyecektir: ![GitHub uygulaması,
incelenen paketlerle ilgili
yorum](/images/guides/features/bundle-size/github-app-with-bundles.png)
