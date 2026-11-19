---
{
  "title": "Yayın kanalları",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist'in CLI'yi canary, sürüm adayı ve kararlı kanallar üzerinden nasıl yayınladığı ve ekibinizi güvenebileceğiniz bir sürüm çizgisine nasıl sabitleyeceğiniz."
}
---

# Yayın kanalları {#release-channels}

Tuist CLI, farklı kararlılık garantileri sunan üç kanal üzerinden dağıtılır. Önerilen kurulum **stable** (kararlı) kanalıdır ve yavaş ilerler: Her özellik birleştiğinde sürüm yükseltilmez; bu sayede güncelleme yapmak artık ilgisiz değişiklikleri topluca kabul etmek anlamına gelmez. Erken benimseyenler **canary** üzerinde commit başına derlemeler çalıştırmaya devam edebilir; **release candidate** (sürüm adayı) kanalı ise ekiplerin, kararlı hale gelmeden önce yaklaşan bir sürüm satırını test etmesine olanak tanır.

## Güncel sürümler {#live-release-status}

Kararlı sürüme yükseltme Pazartesi günleri saat 06:00 UTC’de planlanır. Başarılı bir planlı yükseltmenin ardından, bir sonraki sürüm adayı `main` dalından kesilir ve sonraki canary sürümleri bir sonraki minör sürüme geçer. Yaklaşan zaman aralıklarını ve yamalar ile geri taşımalar dahil son sürümleri görmek için <.localized_link href="/cli/release/calendar">yayın takvimine</.localized_link> bakın.

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## Kanallar {#the-channels}

| Kanal | Sürüm biçimi | Sıklık | Varsayılan olarak çözülür mü? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (ör. `4.201.0-canary.42`) | `main` üzerindeki her commit için | Hayır — açıkça tercih edilmesi gerekir |
| Sürüm adayı | `X.Y.0-rc.N` (ör. `4.200.0-rc.1`) | Her Pazartesi `main` dalından kesilir, ~1 hafta test edilir | Hayır — açıkça tercih edilmesi gerekir |
| Kararlı | `X.Y.Z` (ör. `4.200.0`, `4.200.1`) | Temiz bir test sürecinin ardından her Pazartesi kararlıya yükseltilir | **Evet** |

Canary ve sürüm adayı derlemeleri ön sürüm olarak yayınlanır. Mise ve Homebrew gibi araçlar, `latest`, temel bir kurulum veya bir satır sabitlemesi çözümlerken ön sürümleri dışlar; bu nedenle yalnızca açıkça talep ettiğinizde bu sürümlerden birine ulaşırsınız.

### Canary {#canary}

`main` üzerindeki her commit bir canary sürümü yayınlara. Canary her zaman **bir sonraki yayınlanmamış minör** sürümü temsil eder: Bir sürüm satırı kesildiğinde, `main` bir sonraki minör sürüme geçer (örneğin, `4.200.0-canary.42` değerinden `4.201.0-canary.1` değerine). Canary, en erken sinyali almak isteyen veya raporladığınız ya da katkıda bulunduğunuz bir düzeltmenin kararlı sürüme ulaşmadan önce beklendiği gibi davrandığını doğrulamak isteyen erken benimseyenler için doğru kanaldır.

### Sürüm adayı {#release-candidate}

Bir minör sürüm yayına hazır olduğunda, ilgili satır korumalı bir `releases/<major>.<minor>.x` dalında dondurulur ve `X.Y.0-rc.1` olarak yayınlanır. Satır özellik açısından dondurulur; yalnızca kritik düzeltmeler ve regresyonlar seçilerek eklenir ve kabul edilen her düzeltme RC numarasını artırır (`-rc.2`, `-rc.3`, …). Test süresi sorunsuz tamamlandığında, satır kararlı sürüme yükseltilir.

### Kararlı {#stable}

Kararlı, önerilen kanaldır ve tüm belgeler buna işaret eder. Kararlı bir minör sürüm (`X.Y.0`), yalnızca bir sürüm adayı sorunsuz test edildiğinde yayınlanır ve yeni özellikler `main` ile birleştiğinde **ilerlemez**. Kararlı bir satırdaki yamalar (`X.Y.1`, `X.Y.2`, …) yalnızca geri taşınan düzeltmeleri içerir, asla yeni özellikleri içermez.

## Sürüm seçimi {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> ile (önerilen):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew ile, `brew install --formula tuist` her zaman en son kararlı sürümü kurar; ön sürümler formül üzerinden dağıtılmaz.

## Önerilen strateji {#recommended-strategy}

1. **Kararlı bir satıra sabitleyin**, örneğin `tuist@4.200`. Bu satır yalnızca geri taşınan düzeltmeleri alır, yeni özellikleri almaz; böylece günlük güncellemeler düşük riskli kalır.
2. **Yeni özellikleri bilinçli olarak benimseyin.** Bir sonraki minör sürüme hazır olduğunuzda, onu sürüm adayı kanalında test edin, ardından sabitlemenizi yeni kararlı satıra taşıyın.
3. En erken sinyali almak isteyen bir erken benimseyenseniz, kritik olmayan bir ortamda **canary’yi deneyin**.

## Destek ve geri taşımalar {#support-and-backports}

Her an iki kararlı satır aktif olarak desteklenir:

| Satır | Alır |
| --- | --- |
| Güncel (`X.Y.x`) | Regresyonlar ve güvenlik düzeltmeleri |
| Önceki (`X.(Y-1).x`) | Yalnızca kritik ve güvenlik düzeltmeleri |
| Daha eski | Yok — desteklenen bir satıra yükseltin |

Düzeltmeler ilk olarak `main` (canary) üzerinde yayınlanır. Regresyonlar ve güvenlik düzeltmeleri güncel kararlı satıra geri taşınır, önceki satır ise yalnızca kritik ve güvenlik düzeltmeleri alır. Diğer hata düzeltmeleri geri taşınmaz; bunlar bir sonraki minör sürümle birlikte yayımlanır. Yeni bir satır kararlı sürüme yükseltildiğinde, o anki güncel satır "önceki" haline gelir ve "önceki" olan satır geri taşıma almaz.

Kanaldan bağımsız olarak, Tuist sunucusu son 3 ay içinde yayınlanan herhangi bir CLI ile <.localized_link href="/cli/compatibility">uyumlu</.localized_link> kalır; bu nedenle, bu süre içinde yükseltme yaptığınız sürece kararlı bir satıra sabitlemek sizi desteklenen pencerenin dışına çıkarmaz.
