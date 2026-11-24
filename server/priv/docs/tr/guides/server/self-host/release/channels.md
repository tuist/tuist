---
{
  "title": "Yayın kanalları",
  "titleTemplate": ":title | Kendi Sunucunuzda Barındırma | Server | Kılavuzlar | Tuist",
  "description": "Tuist'in sunucu ve Kura Docker imajlarını canary, yayın adayı ve kararlı kanallar üzerinden nasıl dağıttığı ve dağıtımınızı güvenebileceğiniz bir sürüm hattına sabitleme yöntemleri."
}
---

# Sürüm kanalları {#release-channels}

Tuist sunucusu ve Kura önbellek sunucusu, farklı kararlılık garantileri sunan üç GHCR imaj kanalı üzerinden dağıtılır. Önerilen kurulum **stable** kanalındadır ve haftada bir kez güncellenir: Her özellik `main` ana dalına birleştirildiğinde ilerlemez; bu sayede yükseltme artık birbirinden bağımsız değişiklik yığınlarını absorbe etmek anlamına gelmez. Erken benimseyenler **canary** üzerinde commit başına derlemeler çalıştırmaya devam edebilir; **release candidate** kanalı ise yaklaşan bir sürüm hattını kararlı hale gelmeden önce test etmenize olanak tanır.

Sunucu ve Kura aynı haftalık trenle hareket eder ve ikisi de <.localized_link href="/cli/release/channels">Tuist CLI'nin sürüm takvimi</.localized_link> ile senkronize şekilde çalışır.

## Mevcut sürümler {#live-release-status}

Her bileşenin mevcut sürümleri aşağıda gösterilmektedir. Yaklaşan zaman aralıkları ve son sürümler (yamalar ve geri taşımalar dahil) için <.localized_link href="/guides/server/self-host/release/calendar">sürüm takvimine</.localized_link> bakın.

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## Kanallar {#the-channels}

| Kanal | Sürüm biçimi | Sıklık | `:latest` etiketini ilerletir mi? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (ör. `1.351.0-canary.5`) | `main` ana dalına her commit | Hayır, açıkça seçilmelidir |
| Release candidate | `X.Y.0-rc.N` (ör. `1.351.0-rc.1`) | Her Pazartesi `main` ana dalından kesilir, ~1 hafta bekletilir | Hayır, açıkça seçilmelidir |
| Stable | `X.Y.Z` (ör. `1.350.2`, `1.351.0`) | Temiz bekleme sürecinin ardından her Pazartesi terfi edilir | **Evet** |

Canary ve release-candidate derlemeleri GitHub ön sürümleri olarak yayımlanır. `:latest` çözümlerken ön sürümleri dışlayan herhangi bir araç bunları atlar; dolayısıyla yalnızca açıkça talep ettiğinizde bu sürümlerden birine ulaşırsınız.

### Canary {#canary}

`main` ana dalına yapılan her commit bir canary imajı yayımlar. Canary her zaman **yayımlanmamış sonraki minör sürümü** temsil eder: Bir sürüm hattı kesildiğinde, `main` sonraki minör sürüme ilerler (örneğin, `1.350.0-canary.42` değerinden `1.351.0-canary.1` değerine). Canary, üretim ortamını yansıtan ve gerilemeler konusunda en erken sinyali veren bir hazırlık ortamı için veya bildirdiğiniz bir düzeltmenin kararlı sürüme ulaşmadan önce beklendiği gibi davrandığını doğrulamak için doğru kanaldır.

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

Bir minör sürüm yayımlanmaya hazır olduğunda, ilgili hat korunmuş bir `releases/server-<major>.<minor>.x` (veya `releases/kura-<major>.<minor>.x`) dalında dondurulur ve `X.Y.0-rc.1` olarak yayımlanır. Hat özellik açısından dondurulmuştur; yalnızca kritik düzeltmeler ve gerilemeler cherry-pick yöntemiyle eklenir ve kabul edilen her düzeltme release candidate sürümünü iter (`-rc.2`, `-rc.3` vb.). Bekleme süreci sorunsuz tamamlandıktan sonra hat, takip eden Pazartesi günü stable sürüme terfi edilir.

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable, önerilen kanaldır ve tüm belgeler bu kanala işaret eder. Stable bir minör sürüm (`X.Y.0`), yalnızca bir release candidate temiz bir bekleme sürecinden geçtiğinde yayımlanır ve yeni özellikler `main` ana dalına birleştirildiğinde **ilerlemez**. Stable bir hattaki yamalar (`X.Y.1`, `X.Y.2` vb.) yalnızca geri taşınmış düzeltmeleri içerir, asla yeni özellikleri içermez. `:latest` etiketi yalnızca stable terfisi sırasında ilerler.

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## Pazartesi treni {#the-monday-train}

Her Pazartesi 06:00 UTC'de, üç bileşenin sürüm trenleri senkronize şekilde çalışır:

1. **06:00 UTC** — terfi işleri çalışır. Her biri, henüz stable olmayan en yeni release-candidate hattını terfi eder (genellikle önceki Pazartesi kesilen hat) ve böyle bir hat yoksa hiçbir işlem yapmaz.
2. **Her terfi tamamlandıktan sonra** — release-candidate işi `main` ana dalından sonraki hattı keser; bu sayede yeni kesilen bir hat aynı çalışmada terfi edilmez.

Başarısız bir terfi, kesim işlemini geri tutar: Yalnızca en son stable sürümün üzerindeki en yüksek release-candidate hattı seçilir; bu nedenle başarısızlık üzerine sonraki hattın kesilmesi, yayımlanmayan hattı geride bırakır. Geri tutulan hat, takip eden Pazartesi günü otomatik olarak yeniden denenir.

## Kanal sabitleme {#pinning-a-channel}

Dağıtım manifestinizde, Helm değerlerinde veya Docker Compose dosyanızda istediğiniz belirli etiketi sabitleyin. Örnek olarak Helm şeması kullanımı:

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

Hem `ghcr.io/tuist/tuist` hem de `ghcr.io/tuist/kura` üzerindeki `:latest` en yeni stable sürümü takip eder ve yalnızca Pazartesi terfisi sırasında ilerler. `:latest` etiketini sabitlemek, etiketi güncellemek zorunda kalmadan haftalık stable cadansını sağlar; belirli bir sürümü sabitlemek ise yükseltme zamanı üzerinde tam kontrol sunar.

## Önerilen strateji {#recommended-strategy}

Kanallar, "en yeni düzeltmeleri alma" ile "en yeni özellikleri alma" süreçlerini ayırmanızı sağlar. Güvenli ve düşük efor gerektiren varsayılan yaklaşım şudur:

1. **Üretimi stable bir minör hatta sabitleyin**, örneğin `ghcr.io/tuist/tuist:1.351`. Bu hat yalnızca geri taşınmış düzeltmeleri alır, asla yeni özellikleri almaz; böylece günlük yükseltmeler düşük riskli kalır. Sonraki minör sürümü benimsemeye hazır olduğunuzda sabitlemeyi güncelleyin.
2. **Staging ortamını canary veya belirli bir release-candidate etiketi üzerinde çalıştırın.** Staging, aksi takdirde kullanıcılarınıza ulaşacak regresyonları yakalar ve staging `main` ana dalına ne kadar yakın takip ederse, bunları o kadar erken bulursunuz. Mevcut release-candidate hattı üzerindeki bir staging ortamı iyi bir orta yoldur: Gelecek Pazartesi stable hale gelecek olan tam byte'ları öncesinde test eder.
3. **Gerçekten yayımlananları görmek için [Sunucu değişiklik günlüğünü](/changelog) takip edin.** Her stable terfi, dahil edilen çekme isteklerinin listesiyle birlikte burada duyurulur.

Yeni özelliklerin stable hale geldikçe üretime otomatik olarak yayılmasını tercih ediyorsanız, üretimi `:latest` üzerinde tutun. Etiketin her Pazartesi sabahı haftalık olarak ilerlediğini unutmayın; bu nedenle dağıtım pencerenizi buna göre planlayın.

## Geri taşımalar {#backports}

Her zaman iki stable sunucu (ve Kura) hattı aktif olarak bakım altındadır: mevcut hat, regresyon ve güvenlik düzeltmelerini geri taşıma pull requestleri olarak alır; önceki hat ise yalnızca kritik ve güvenlik düzeltmelerini alır. Daha eski hatlara geri taşıma yapılmaz; düzeltmeleri almak için bakımı devam eden bir hatta yükseltin. Yeni bir hat stable'a terfi edildiğinde, o anda mevcut olan hat "önceki" haline gelir ve "önceki" olan hat geri taşıma almaya son verir.

Geri taşımalar, talep üzerine `X.Y.(Z+1)` yama sürümleri olarak kesilir. Asla `:latest` etiketini ilerletmezler.
