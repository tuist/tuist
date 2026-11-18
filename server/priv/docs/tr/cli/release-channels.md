---
{
  "title": "Yayın kanalları",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist'in CLI'yi canary, sürüm aday ve kararlı kanallar üzerinden nasıl yayınladığı ve ekibinizi güvenebileceğiniz bir sürüm çizgisine nasıl sabitleyeceğiniz."
}
---

# Sürüm kanalları {#release-channels}

Tuist CLI, farklı kararlılık garantileri sunan üç kanal üzerinden dağıtılır. Önerilen kurulum **stable** kanalındadır ve yavaş ilerler: her özellik birleştiğinde sürüm atlamaz, bu nedenle yükseltme artık ilgisiz değişiklik topluluklarını kabul etmek anlamına gelmez. Erken benimseyenler **canary** üzerinde commit başına derlemeler çalıştırabilir; **release candidate** kanalı ise ekiplerin yaklaşan bir satırı kararlı hale gelmeden önce denemesine olanak tanır.

## Kanallar {#the-channels}

| Kanal | Sürüm biçimi | Sıklık | Varsayılan olarak çözümlenir mi? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (ör. `4.201.0-canary.42`) | `main` üzerindeki her commit | Hayır — açıkça seçilmeli |
| Release candidate | `X.Y.0-rc.N` (ör. `4.200.0-rc.1`) | Her Pazartesi `main` üzerinden kesilir, ~1 hafta bekletilir | Hayır — açıkça seçilmeli |
| Stable | `X.Y.Z` (ör. `4.200.0`, `4.200.1`) | Temiz bir bekleme sürecinin ardından her Pazartesi terfi edilir | **Evet** |

Canary ve release candidate derlemeleri ön sürüm olarak yayımlanır. Mise ve Homebrew gibi araçlar, `latest`, temel bir kurulum veya bir satır sabitlemesi çözümlerken ön sürümleri dışlar; bu nedenle yalnızca açıkça talep ettiğinizde bunlardan birine ulaşırsınız.

### Canary {#canary}

`main` üzerindeki her commit bir canary yayımlar. Canary her zaman **yayınlanmamış sonraki minör** sürümü temsil eder: bir satır yayın için kesildiğinde, `main` sonraki minöre ilerler (örneğin, `4.200.0-canary.42` değerinden `4.201.0-canary.1` değerine). Canary, en erken sinyali almak isteyen erken benimseyenler için veya raporladığınız ya da katkıda bulunduğunuz bir düzeltmenin kararlı kanala ulaşmadan önce beklendiği gibi davrandığını doğrulamak için doğru kanaldır.

### Release candidate {#release-candidate}

Bir minör sürüm yayına hazır olduğunda, ilgili satır korumalı bir `releases/<major>.<minor>.x` dalına dondurulur ve `X.Y.0-rc.1` olarak yayımlanır. Satır özellik açısından dondurulur; yalnızca kritik düzeltmeler ve gerilemeler cherry-pick ile alınır ve kabul edilen her düzeltme RC numarasını artırır (`-rc.2`, `-rc.3`, …). Bekleme süreci sorunsuz tamamlandığında satır stable’a terfi edilir.

### Stable {#stable}

Stable, önerilen kanaldır ve tüm belgeler bu kanala işaret eder. Kararlı bir minör sürüm (`X.Y.0`), yalnızca bir release candidate sorunsuz bekleme sürecinden geçtiğinde yayımlanır ve yeni özellikler `main` üzerine birleştiğinde **ilerlemez**. Kararlı bir satırdaki yamalar (`X.Y.1`, `X.Y.2`, …) yalnızca geriye taşınmış düzeltmeleri içerir, asla yeni özellikleri içermez.

## Sürüm seçimi {#choosing-a-version}

<.localized_link href="/guides/install-tuist">Mise</.localized_link> ile (önerilen):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Homebrew ile, `brew install --formula tuist` her zaman en son stable sürümü kurar; ön sürümler formula aracılığıyla dağıtılmaz.

## Önerilen strateji {#recommended-strategy}

1. **Kararlı bir satıra sabitleyin**, örneğin `tuist@4.200`. Bu satır yalnızca geriye taşınmış düzeltmeleri alır, yeni özellikleri almaz; böylece günlük yükseltmeler düşük riskli kalır.
2. **Yeni özellikleri bilinçli olarak benimseyin.** Sonraki minör sürüme hazır olduğunuzda, onu release candidate kanalında bekletin, ardından sabitlemenizi yeni kararlı satıra taşıyın.
3. En erken sinyali almak isteyen bir erken benimseyiciyseniz, kritik olmayan bir ortamda **canary’yi deneyin**.

## Destek ve geriye taşımalar {#support-and-backports}

Her zaman iki kararlı satır aktif olarak desteklenir:

| Satır | Alır |
| --- | --- |
| Geçerli (`X.Y.x`) | Gerilemeler ve güvenlik düzeltmeleri |
| Önceki (`X.(Y-1).x`) | Yalnızca kritik ve güvenlik düzeltmeleri |
| Daha eski | Yok — desteklenen bir satıra yükseltin |

Düzeltmeler öncelikle `main` (canary) üzerine gelir. Gerilemeler ve güvenlik düzeltmeleri geçerli kararlı satıra geriye taşınır, önceki satır ise yalnızca kritik ve güvenlik düzeltmeleri alır. Diğer hata düzeltmeleri geriye taşınmaz; bir sonraki minör sürümle birlikte yayımlanır. Yeni bir satır stable’a terfi edildiğinde, o ana kadar geçerli olan satır "önceki" haline gelir ve "önceki" olarak işaretlenen satır geriye taşıma almaz.

Kanaldan bağımsız olarak, Tuist sunucusu son 3 ay içinde yayımlanan herhangi bir CLI ile <.localized_link href="/cli/compatibility">uyumlu</.localized_link> kalır; bu nedenle, bu süre içinde yükseltme yaptığınız sürece kararlı bir satıra sabitlemek sizi destek penceresinin dışına çıkarmaz.
