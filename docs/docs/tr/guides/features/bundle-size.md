---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Paket içgörüleri {#bundle-size}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</LocalizedLink>
<!-- -->
:::

Uygulamanıza daha fazla özellik ekledikçe, uygulama paketinizin boyutu da
büyümeye devam eder. Daha fazla kod ve varlık gönderdikçe paket boyutundaki
büyümenin bir kısmı kaçınılmaz olsa da, varlıklarınızın paketlerinizde
yinelenmemesini sağlamak veya kullanılmayan ikili sembolleri çıkarmak gibi bu
büyümeyi en aza indirmenin birçok yolu vardır. Tuist, uygulama boyutunuzun küçük
kalmasına yardımcı olacak araçlar ve içgörüler sağlar ve ayrıca uygulama
boyutunuzu zaman içinde izler.

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

`tuist inspect bundle` komutu paketi analiz eder ve paketin içeriğinin taranması
veya modül dökümü de dahil olmak üzere paketin ayrıntılı bir genel görünümünü
görmeniz için size bir bağlantı sağlar:

![Analiz edilen paket](/images/guides/features/bundle-size/analyzed-bundle.png)

## Sürekli entegrasyon {#continuous-integration}

Zaman içinde paket boyutunu izlemek için CI üzerindeki paketi analiz etmeniz
gerekecektir. Öncelikle, CI'nızın
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>
olduğundan emin olmanız gerekir:

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

Kurulduktan sonra, paket boyutunuzun zaman içinde nasıl geliştiğini
görebileceksiniz:

![Paket boyutu
grafiği](/images/guides/features/bundle-size/bundle-size-graph.png)

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git platformuyla</LocalizedLink> entegre edin.
<!-- -->
:::

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuza bağlandıktan
sonra, `tuist inspect bundle` çalıştırdığınızda Tuist doğrudan çekme/birleştirme
isteklerinize bir yorum gönderecektir: ![GitHub app comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
