---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Kararsız Testler {#flaky-tests}

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">Test
  Insights</LocalizedLink> yapılandırılmalıdır.
<!-- -->
:::

Kararsız testler, aynı kodla birden çok kez çalıştırıldığında farklı sonuçlar
(başarılı veya başarısız) veren testlerdir. Bu testler, test paketine olan
güveni zedeler ve geliştiricilerin yanlış başarısızlıkları araştırmak için zaman
kaybetmelerine neden olur. Tuist, kararsız testleri otomatik olarak algılar ve
bunları zaman içinde takip etmenize yardımcı olur.

![Flaky Tests
sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Dengesiz algılama nasıl çalışır? {#how-it-works}

Tuist, iki şekilde hatalı testleri algılar:

### Test tekrarları {#test-retries}

Xcode'un yeniden deneme işlevini kullanarak testler yaptığınızda (
`-retry-tests-on-failure` veya `-test-iterations` kullanarak), Tuist her
denemenin sonuçlarını analiz eder. Bir test bazı denemelerde başarısız olurken
diğerlerinde başarılı olursa, bu test "kararsız" olarak işaretlenir.

Örneğin, bir test ilk denemede başarısız olur ancak yeniden denemede başarılı
olursa, Tuist bunu dengesiz test olarak kaydeder.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Flaky test case
detail](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Çapraz çalıştırma algılama {#cross-run-detection}

Test tekrarları olmasa bile, Tuist aynı taahhütte farklı CI çalıştırmalarındaki
sonuçları karşılaştırarak dengesiz testleri tespit edebilir. Bir test bir CI
çalıştırmasında başarılı olurken, aynı taahhütte başka bir çalıştırmada
başarısız olursa, her iki çalıştırma da dengesiz olarak işaretlenir.

Bu, yeniden denemelerle yakalanamayacak kadar tutarlı bir şekilde başarısız
olmayan, ancak yine de aralıklı CI hatalarına neden olan dengesiz testleri
yakalamak için özellikle yararlıdır.

## Kararsız testleri yönetme {#managing-flaky-tests}

### Otomatik temizleme

Tuist, 14 gün boyunca hatalı olmayan testlerden hatalı bayrağını otomatik olarak
siler. Bu, düzeltilen testlerin süresiz olarak hatalı olarak işaretli
kalmamasını sağlar.

### Manuel yönetim

Test durum ayrıntıları sayfasından testleri manuel olarak dengesiz olarak
işaretleyebilir veya işaretini kaldırabilirsiniz. Bu, aşağıdaki durumlarda
yararlıdır:
- Düzeltme üzerinde çalışırken bilinen bir hatalı testi onaylamak istiyorsunuz.
- Altyapı sorunları nedeniyle bir test yanlış bir şekilde işaretlendi.

## Slack bildirimleri {#slack-notifications}

Slack entegrasyonunuzda
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">flaky test
alerts</LocalizedLink> ayarlayarak, bir testin dengesiz hale geldiğinde anında
bildirim alın.
