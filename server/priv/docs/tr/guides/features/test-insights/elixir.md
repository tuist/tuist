---
{
  "title": "Elixir Test İçgörileri",
  "titleTemplate": ":title · Test İçgörileri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Elixir projenizin testlerini Tuist kontrol panelinde takip edin."
}
---
# Elixir test içgörüleri {#elixir-test-insights}

Tuist'in Hex paketi, her test çalıştırmasından sonra Elixir projenizin test sonuçlarını yükler ve Tuist kontrol panelinde test performansını ve kararsız testleri doğrudan görmenizi sağlar.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixir ile başlayın</.localized_link> kılavuzunu tamamlayın

## Test çalıştırmalarınızı bildirin {#report-your-test-runs}

Paylaşılan kurulum test entegrasyonunu yükler. Aynı bağımsız değişkenler, çıkış ve çıkış koduyla `mix test` kullanmaya devam edin:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist, çalıştırma bittiğinde bildirimi yapar; ek bir test takma adına gerek yoktur.

Test içgörülerinize Tuist kontrol panelinden erişebilir ve zaman içinde nasıl değiştiğini görebilirsiniz:

![Bir Phoenix uygulamasının test kontrol paneli](/images/guides/features/elixir/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Paket, ExUnit sonuçlarını toplar; bunlar şunları içerir:
- Tekil testlerin geçme/kalma durumu ve süresi
- Her testin ait olduğu modül ve `describe` bloğu
- Her başarısızlığın mesajı ve konumu
- Çalıştırmalar arasında kararsız test tespiti
- Dal ve commit bilgisi; sürekli entegrasyonda sağlayıcı ve çalıştırma bilgisi
- Sürekli entegrasyonda, checkout'un [Git geçmişini](#git-history)

Doctest'ler diğer testler gibi bildirilir. `--cover` ile, çalıştırmanın satır kapsamı da yüklenir: bkz. <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir kod kapsamı</.localized_link>.

> [!NOTE]
> Paket, zaten kullandığınız biçimlendiricilerin yanına eklediği bir ExUnit biçimlendirici aracılığıyla raporlama yapar. Komut satırında `--formatter` geçirirseniz Mix tüm listeyi değiştirir; bu nedenle çalıştırma bildirilmez ve görev sizi bu konuda uyarır.

### Git geçmişi {#git-history}

Sürekli entegrasyonda paket ayrıca checkout'un commit geçmişini de yükler: commit SHA'ları, ebeveynleri, commit tarihleri ve çalıştırmanın ile pull request'in temel dalının bulunduğu dal bilgisi. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgi, Tuist'e varsayılan dalınıza hangi commit'lerin geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit'ler. Paket, checkout'ta zaten bulunan geçmişi okur ve checkout temel dalı içermiyorsa uzaktan en son commit'i ister (`git ls-remote`). Kod kapsamı dışında (`--cover`), geçmiş çekilmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuya bağlanmaz. |

## Sorun giderme {#troubleshooting}

Raporlama, testlerinizin sonucunu asla değiştirmez: rapor gönderilemezse çalıştırma normal şekilde sonlanır ve hiçbir şey yazdırılmaz. Bir raporun neden gönderilmediğini görmek için `TUIST_DEBUG=1` ayarlayın:

```bash
TUIST_DEBUG=1 mix test
```
