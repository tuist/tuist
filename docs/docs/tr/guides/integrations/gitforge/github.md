---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# GitHub entegrasyonu {#github}

Git depoları, yazılım projelerinin büyük çoğunluğunun en önemli parçasıdır.
Tuist içgörülerini doğrudan çekme isteklerinizde sağlamak ve varsayılan dalınızı
senkronize etmek gibi bazı yapılandırmalardan sizi kurtarmak için GitHub ile
entegre oluyoruz.

## Kurulum {#setup}

Tuist GitHub uygulamasını kuruluşunuzun `Integrations` sekmesine yüklemeniz
gerekecektir: ![Entegrasyonlar sekmesini gösteren bir
resim](/images/guides/integrations/gitforge/github/integrations.png)

Bundan sonra, GitHub deponuz ile Tuist projeniz arasında bir proje bağlantısı
ekleyebilirsiniz:

![Proje bağlantısının eklenmesini gösteren bir
görüntü](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Çekme/birleştirme isteği yorumları {#pull-merge-request-comments}

GitHub uygulaması, en son
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>
veya
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>
bağlantıları da dahil olmak üzere PR'nin bir özetini içeren bir Tuist çalıştırma
raporu yayınlar:

![Çekme isteği yorumunu gösteren bir
resim](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Yorum yalnızca CI çalışmalarınız
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>
olduğunda yayınlanır.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
PR işlemiyle değil de örneğin GitHub yorumuyla tetiklenen özel bir iş akışınız
varsa `GITHUB_REF` değişkeninin `refs/pull/<pr_number>/merge` veya
`refs/pull/<pr_number>/head` olarak ayarlandığından emin olmanız
gerekebilir.</pr_number></pr_number>

İlgili komutu çalıştırabilirsiniz, örneğin `tuist share`, ön ekli `GITHUB_REF`
ortam değişkeni ile: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
