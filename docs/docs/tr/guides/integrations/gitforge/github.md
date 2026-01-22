---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub entegrasyonu {#github}

Git depoları, mevcut yazılım projelerinin büyük çoğunluğunun merkezinde yer
alır. GitHub ile entegre olarak, pull isteklerinize Tuist içgörülerini ekler ve
varsayılan dalınızı senkronize etmek gibi bazı yapılandırma işlemlerinden sizi
kurtarırız.

## Kurulum {#setup}

`'un Entegrasyonlar` sekmesinde Tuist GitHub uygulamasını yüklemeniz
gerekecektir: ![Entegrasyonlar sekmesini gösteren bir
resim](/images/guides/integrations/gitforge/github/integrations.png)

Bundan sonra, GitHub deponuz ile Tuist projeniz arasında bir proje bağlantısı
ekleyebilirsiniz:

![Proje bağlantısının eklendiğini gösteren bir
resim](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Çekme/birleştirme isteği yorumları {#pull-merge-request-comments}

GitHub uygulaması, en son
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">önizlemeler</LocalizedLink>
veya
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">testler</LocalizedLink>
bağlantılarını içeren PR özetini içeren bir Tuist çalıştırma raporu yayınlar:

![Çekme isteği yorumunu gösteren bir
resim](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Yorum, CI çalıştırmalarınız
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">doğrulanmış</LocalizedLink>
olduğunda yayınlanır.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
PR commit'inde tetiklenmeyen, ancak örneğin GitHub yorumunda tetiklenen özel bir
iş akışınız varsa, `GITHUB_REF` değişkeninin `refs/pull/<pr_number>/merge` veya
`refs/pull/<pr_number>/head` olarak ayarlandığından emin olmanız
gerekebilir.</pr_number></pr_number>

`tuist share` gibi ilgili komutu, `GITHUB_REF` ortam değişkeni ile
çalıştırabilirsiniz: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
