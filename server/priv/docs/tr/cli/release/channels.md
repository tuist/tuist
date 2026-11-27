---
{
  "title": "Yayın kanalları",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist'in CLI'yi canary, sürüm aday ve kararlı kanallar üzerinden nasıl dağıttığı ve ekibinizi güvenebileceğiniz bir sürüm hattına nasıl sabitleyeceğiniz."
}
---

# Yayın kanalları {#release-channels}

Tuist CLI, farklı kararlılık garantileri sunan üç kanal üzerinden dağıtılır. Önerilen kurulum **kararlı** kanaldır ve yavaş ilerler: Her özellik birleştirildiğinde sürüm yükseltilmez; bu sayede güncelleme yapmak artık ilgisiz değişiklik yığınlarını kabul etmek anlamına gelmez. Erken benimseyenler, **canary** üzerinde commit başına derlemeleri çalıştırabilir ve **yayın adayı** kanalı, ekiplerin gelecek bir satırı kararlı hale gelmeden önce test etmesine olanak tanır.

## Mevcut sürümler {#live-release-status}

Kararlı sürüm terfisi Pazartesi günleri saat 06:00 UTC'de planlanır. Başarılı bir planlanmış terfiden sonra, bir sonraki yayın adayı `main` üzerinden kesilir ve随后的 canary sürümleri bir sonraki minör sürüme geçer. Yaklaşan zaman pencerelerini ve yamalar ile geri taşımalar dahil son sürümleri görmek için <.localized_link href="/cli/release/calendar">yayın takvimine</.localized_link> bakın.

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## Kanallar {#the-channels}

| Kanal | Sürüm formatı | Sıklık | Varsayılan olarak çözümlenir mi? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (örn. `4.201.0-canary.42`) | `main` üzerindeki her commit için | Hayır — açıkça opt-in gerekir |
| Yayın adayı | `X.Y.0-rc.N` (örn. `4.200.0-rc.1`) | Her Pazartesi `main` üzerinden kesilir, ~1 hafta bekletilir | Hayır — açıkça opt-in gerekir |
| Kararlı | `X.Y.Z` (örn. `4.200.0`, `4.200.1`) | Temiz bir bekleme sürecinin ardından her Pazartesi terfi edilir | **Evet** |

Canary ve yayın adayı derlemeleri ön sürüm olarak yayımlanır. Mise ve Homebrew gibi araçlar, `latest`, boş bir kurulum veya bir satır sabitlemesi çözümlerken ön sürümleri hariç tutar; bu nedenle yalnızca açıkça talep ettiğinizde bu sürümlerden birine ulaşırsınız.

### Canary {#canary}

`main` üzerindeki her commit bir canary sürümü yayımlar. Canary her zaman **yayınlanmamış bir sonraki minör** sürümü temsil eder: Bir satır yayın için kesildiğinde, `main` bir sonraki minör sürüme geçer (örneğin, `4.200.0-canary.42` değerinden `4.201.0-canary.1` değerine). Canary, en erken sinyali almak isteyen erken benimseyenler veya bildirdiğiniz ya da katkıda bulunduğunuz bir düzeltmenin kararlı sürüme ulaşmadan önce beklendiği gibi davrandığını doğrulamak isteyenler için doğru kanaldır.

### Yayın adayı {#release-candidate}

Bir minör sürüm yayına hazır olduğunda, satırı korumalı bir `releases/<major>.<minor>.x` dalında dondurulur ve `X.Y.0-rc.1` olarak yayımlanır. Satır özellik açısından dondurulur; yalnızca kritik düzeltmeler ve gerilemeler seçilerek alınır ve kabul edilen her düzeltme RC sürümünü artırır (`-rc.2`, `-rc.3`, …). Bekleme süreci sorunsuz tamamlandığında, satır kararlı sürüme terfi edilir.

### Kararlı {#stable}

Kararlı, önerilen kanaldır ve tüm belgelerin işaret ettiği kanaldır. Kararlı bir minör sürüm (`X.Y.0`), yalnızca bir yayın adayı sorunsuz bir bekleme sürecinden geçtiğinde yayımlanır ve yeni özellikler `main` üzerine birleştirildiğinde **ilerlemez**. Kararlı bir satırdaki yamalar (`X.Y.1`, `X.Y.2`, …) yalnızca geri taşınan düzeltmeleri içerir, asla yeni özellikler içermez.

## Sürüm seçimi {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> ile (önerilen):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew ile, `brew install --formula tuist` her zaman en son kararlı sürümü yükler; ön sürümler formül aracılığıyla dağıtılmaz.

## Önerilen strateji {#recommended-strategy}

1. **Kararlı bir satıra sabitleyin**, örneğin `tuist@4.200`. Bu satır yalnızca geri taşınan düzeltmeleri alır, asla yeni özellikler almaz; bu sayede günlük güncellemeler düşük riskli kalır.
2. **Yeni özellikleri bilinçli olarak benimseyin.** Bir sonraki minör sürüme hazır olduğunuzda, onu yayın adayı kanalında bekletin, ardından sabitlemenizi yeni kararlı satıra taşıyın.
3. En erken sinyali almak isteyen bir erken benimseyiciyseniz, kritik olmayan bir ortamda **canary'yi deneyin**.

## Destek ve geri taşımalar {#support-and-backports}

Herhangi bir zamanda iki kararlı satır aktif olarak korunur:

| Satır | Alır |
| --- | --- |
| Mevcut (`X.Y.x`) | Gerilemeler ve güvenlik düzeltmeleri |
| Önceki (`X.(Y-1).x`) | Yalnızca kritik ve güvenlik düzeltmeleri |
| Daha eski | Hiçbiri — bakımı devam eden bir satıra yükseltin |

Düzeltmeler ilk olarak `main` (canary) üzerine gelir. Gerilemeler ve güvenlik düzeltmeleri mevcut kararlı satıra geri taşınır, önceki satır ise yalnızca kritik ve güvenlik düzeltmeleri alır. Diğer hata düzeltmeleri geri taşınmaz; bir sonraki minör sürümle birlikte yayımlanır. Yeni bir satır kararlı sürüme terfi edildiğinde, mevcut olan satır "önceki" haline gelir ve "önceki" olan satır geri taşıma almaz.

Kanaldan bağımsız olarak, Tuist sunucusu son 3 ay içinde yayımlanan herhangi bir CLI ile <.localized_link href="/cli/compatibility">uyumlu</.localized_link> kalır; bu nedenle, bu süre içinde yükseltme yaptığınız sürece kararlı bir satıra sabitlemek sizi destek penceresinin dışına çıkarmaz.
