---
{
  "title": "Elixir Test İçgörileri",
  "titleTemplate": ":title · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Elixir projenizin testlerini Tuist panosunda takip edin."
}
---
# Elixir test içgörüleri {#elixir-test-insights}

Tuist'in Hex paketi, her test çalıştırmasından sonra Elixir projenizin test sonuçlarını yükler ve Tuist kontrol panelinde test performansı ile kararsız testler hakkında doğrudan görünürlük sağlar.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixir ile başlayın</.localized_link> kılavuzunu tamamlayın

## Test çalıştırmalarınızı bildirin {#report-your-test-runs}

Paylaşılan kurulum, test entegrasyonunu yükler. Aynı bağımsız değişkenler, çıktı ve çıkış koduyla `mix test` kullanmaya devam edin:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist, çalıştırma bittiğinde bildirimi gönderir; ek bir test takma adına gerek yoktur.

Test içgörülerinize Tuist kontrol panelinden erişebilir ve zaman içindeki gelişimini görebilirsiniz:

![Bir Phoenix uygulamasının test kontrol paneli](/images/guides/features/elixir/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Paket, ExUnit sonuçlarını toplar; bunlar şunları içerir:
- Tekil testlerin geçme/kalma durumu ve süresi
- Her testin ait olduğu modül ve `describe` bloğu
- Her başarısızlığın mesajı ve konumu
- Çalıştırmalar arasında kararsız test tespiti
- Dal ve commit; sürekli entegrasyonda sağlayıcı ve çalıştırma
- Sürekli entegrasyonda, checkout'un [Git geçmişi](#git-history)

Doctest'ler diğer testler gibi bildirilir. `--cover` ile birlikte, çalıştırmanın satır kapsamı da yüklenir: bkz. <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir kod kapsamı</.localized_link>.

> [!NOTE]
> Paket, zaten kullandığınız formatörlerin yanına eklediği bir ExUnit formatörü aracılığıyla bildirim yapar. Komut satırında `--formatter` belirtirseniz Mix tüm listeyi değiştirir; bu nedenle çalıştırma bildirilmez ve görev sizi bu konuda uyarır.

### Git geçmişi {#git-history}

Sürekli entegrasyonda paket ayrıca checkout'un commit geçmişini de yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist'e varsayılan dalınıza hangi commit'lerin geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit'ler. Paket, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında uzaktan en son commit'i ister (`git ls-remote`). Kod kapsamı dışında (`--cover`), geçmiş çekilmez. Kod kapsamıyla birlikte, dosya içerikleri olmadan sığ bir checkout derinleştirilir; böylece bir pull request'in nereden dallandığı bulunur ve sürekli entegrasyonda Tuist'in zaten sahip olduğu commit'lere ulaşılır; bu sayede bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuya bağlanmaz. |
| `TUIST_GIT_BRANCH=<branch>` | Çalıştırmanın dalını adlandırır; CI sağlayıcısının ve checkout'un belirlediği dalın önüne geçer. Dal yerine bir commit checkout eden ve aksi takdirde çalıştırmalarında dal bilgisi olmayan, Tuist'in tanımadığı CI sistemlerinde bunu ayarlayın. |

## Sorun giderme {#troubleshooting}

Bildirim, testlerinizin sonucunu hiçbir zaman değiştirmez: bildirim gönderilemezse çalıştırma normalde çıkacağı şekilde çıkar ve hiçbir şey yazdırılmaz. Bir bildirimin neden gönderilmediğini görmek için `TUIST_DEBUG=1` ayarlayın:

```bash
TUIST_DEBUG=1 mix test
```
