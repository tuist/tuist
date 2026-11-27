---
{
  "title": "Yayın kanalları",
  "titleTemplate": ":title | Kendi Sunucunuzda Barındırma | Server | Kılavuzlar | Tuist",
  "description": "Tuist'in sunucu ve Kura Docker imajlarını canary, sürüm adayı ve kararlı kanallar üzerinden nasıl dağıttığını ve dağıtımınızı güvenebileceğiniz bir sürüm hattına nasıl sabitleyeceğinizi öğrenin."
}
---

# Yayın kanalları {#release-channels}

Tuist sunucusu ve Kura önbellek sunucusu, farklı kararlılık garantileri sunan üç GHCR imaj kanalı üzerinden yayınlanır. Önerilen kurulum **stable** kanalındadır ve haftada bir kez güncellenir: her özellik `main` ana dalına birleştirildiğinde ilerlemez, bu nedenle yükseltme artık ilgisiz değişiklik yığınlarını kabul etmek anlamına gelmez. Erken benimseyenler hâlâ **canary** üzerinde commit başına derlemeler çalıştırabilir ve **release candidate** kanalı, yaklaşan bir sürüm satırının kararlı hale gelmeden önce test edilmesine olanak tanır.

Sunucu ve Kura aynı haftalık trenle hareket eder ve ikisi de <.localized_link href="/cli/release/channels">Tuist CLI'nin yayın takvimi</.localized_link> ile tam senkronize şekilde çalışır.

## Mevcut sürümler {#live-release-status}

Her bileşenin mevcut sürümleri aşağıda gösterilmektedir. Yaklaşan zaman aralıkları ve yamalar ile geri taşımalar dahil son sürümler için <.localized_link href="/guides/server/self-host/release/calendar">yayın takvimine</.localized_link> bakın.

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## Kanallar {#the-channels}

| Kanal | Sürüm biçimi | Sıklık | `:latest` ilerler mi? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (örn. `1.351.0-canary.5`) | `main` ana dalına yapılan her commit | Hayır, açıkça seçilmelidir |
| Release candidate | `X.Y.0-rc.N` (örn. `1.351.0-rc.1`) | Her Pazartesi `main` ana dalından kesilir, ~1 hafta bekletilir | Hayır, açıkça seçilmelidir |
| Stable | `X.Y.Z` (örn. `1.350.2`, `1.351.0`) | Temiz bir bekleme sürecinin ardından her Pazartesi terfi ettirilir | **Evet** |

Canary ve release candidate derlemeleri GitHub ön sürümleri olarak yayınlanır. `:latest` çözümlerken ön sürümleri dışlayan herhangi bir araç bunları atlayacaktır, bu nedenle yalnızca açıkça talep ettiğinizde bu sürümlere ulaşırsınız.

### Canary {#canary}

`main` ana dalına yapılan her commit bir canary imajı yayınlar. Canary her zaman **sonraki yayınlanmamış minör** sürümü temsil eder: bir sürüm satırı kesildiğinde, `main` sonraki minör sürüme ilerler (örneğin, `1.350.0-canary.42` değerinden `1.351.0-canary.1` değerine). Canary, üretimi yansıtan ve regresyonlar konusunda en erken sinyali veren veya bildirdiğiniz bir düzeltmenin kararlı sürüme ulaşmadan önce beklendiği gibi davrandığını doğrulamanızı sağlayan bir staging ortamı için doğru kanaldır.

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

Bir minör sürüm yayına hazır olduğunda, satırı korumalı bir `releases/server-<major>.<minor>.x` (veya `releases/kura-<major>.<minor>.x`) dalında dondurulur ve `X.Y.0-rc.1` olarak yayınlanır. Satır özellik açısından dondurulmuştur; yalnızca kritik düzeltmeler ve regresyonlar üzerine cherry-pick ile eklenir ve kabul edilen her düzeltme release candidate sürümünü yinelemeli olarak artırır (`-rc.2`, `-rc.3` vb.). Bekleme süresi temiz bir şekilde tamamlandıktan sonra, satır ertesi Pazartesi stable olarak terfi ettirilir.

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable önerilen kanaldır ve tüm belgeler bu kanala yönlendirir. Kararlı bir minör sürüm (`X.Y.0`), yalnızca bir release candidate temiz bir bekleme sürecinden geçtiğinde yayınlanır ve yeni özellikler `main` ana dalına birleştirildiğinde **ilerlemez**. Kararlı bir satırdaki yamalar (`X.Y.1`, `X.Y.2` vb.) yalnızca geri taşınan düzeltmeleri içerir, asla yeni özellikleri içermez. `:latest` yalnızca stable terfisi sırasında ilerler.

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## Pazartesi treni {#the-monday-train}

Her Pazartesi UTC 06:00'da, üç bileşenin yayın trenleri tam senkronize şekilde çalışır:

1. **UTC 06:00** — terfi işleri çalışır. Her biri, henüz stable olmayan en yeni release candidate satırını (genellikle önceki Pazartesi kesilen satır) terfi ettirir ve böyle bir satır yoksa hiçbir işlem yapmaz.
2. **Her terfi tamamlandıktan sonra** — release candidate işi `main` ana dalından sonraki satırı keser, bu nedenle yeni kesilen bir satır aynı çalışmada asla terfi ettirilmez.

Başarısız bir terfi, kesme işlemini geri tutar: yalnızca en son stable sürümün üzerindeki en yüksek release candidate satırı seçilir, bu nedenle başarısızlık üzerine sonraki satırı kesmek, yayınlanmayan satırı mahsur bırakır. Ertesi Pazartesi geri tutulan satır otomatik olarak yeniden denenir.

## Kanal sabitleme {#pinning-a-channel}

Dağıtım manifestinizde, Helm değerlerinde veya Docker Compose dosyanızda istediğiniz belirli etiketi sabitleyin. Örnek olarak, Helm şemasını kullanırken:

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

Hem `ghcr.io/tuist/tuist` hem de `ghcr.io/tuist/kura` üzerindeki `:latest`, en yeni stable sürümü takip eder ve yalnızca Pazartesi terfisi sırasında ilerler. `:latest` sabitlemek, etiketi güncellemek zorunda kalmadan haftalık stable ritmini sağlar; belirli bir sürümü sabitlemek ise yükseltme zamanı üzerinde tam kontrol sunar.

## Önerilen strateji {#recommended-strategy}

Kanallar, "en yeni düzeltmeleri alma" ile "en yeni özellikleri alma" süreçlerini ayırmanızı sağlar. Güvenli ve düşük çaba gerektiren varsayılan yaklaşım şudur:

1. **Üretimi kararlı bir minör satıra sabitleyin**, örneğin `ghcr.io/tuist/tuist:1.351`. Bu satır yalnızca geri taşınan düzeltmeleri alır, asla yeni özellikleri almaz, bu nedenle günlük yükseltmeler düşük riskli kalır. Sonraki minör sürümü benimsemeye hazır olduğunuzda sabitlemeyi güncelleyin.
2. **Staging ortamını canary veya belirli bir release candidate etiketi üzerinde çalıştırın.** Staging, aksi takdirde kullanıcılarınıza ulaşacak regresyonları yakalar ve staging `main` ana dalına ne kadar yakın takip ederse, onları o kadar erken bulursunuz. Mevcut release candidate satırı üzerindeki bir staging ortamı iyi bir orta yoldur: gelecek Pazartesi stable hale gelecek olan baytları tam olarak test eder.
3. **Gerçekten yayınlananlar için [Sunucu değişiklik günlüğünü](/changelog) takip edin.** Her stable terfi, içine alınan pull request listesiyle birlikte burada duyurulur.

Yeni özelliklerin stable hale geldikçe üretime otomatik olarak yayılmasını tercih ediyorsanız, üretimi `:latest` üzerinde tutun. Etiketin her Pazartesi sabahı haftalık olarak ilerlediğini unutmayın, bu nedenle dağıtım pencerenizi buna göre planlayın.

## Geri taşımalar {#backports}

Her zaman iki stable sunucu (ve Kura) satırı aktif olarak bakımı yapılır: mevcut satır, geri taşıma pull requestleri olarak regresyon ve güvenlik düzeltmelerini alır; önceki satır ise yalnızca kritik ve güvenlik düzeltmelerini alır. Daha eski satırlara geri taşıma yapılmaz; düzeltmeleri almak için bakımı yapılan bir satıra yükseltin. Yeni bir satır stable olarak terfi ettirildiğinde, o anki mevcut satır "önceki" haline gelir ve "önceki" olan satır geri taşıma almayı durdurur.

Geri taşımalar, talep üzerine `X.Y.(Z+1)` yama sürümleri olarak kesilir. Asla `:latest` öğesini hareket ettirmezler.
