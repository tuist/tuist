---
{
  "title": "Elixir Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Elixir projenizin testlerini Tuist panosunda takip edin."
}
---
# Elixir test içgörüleri {#elixir-test-insights}

Tuist'in Hex paketi, her test çalıştırmasından sonra Elixir projenizin test sonuçlarını yükler; böylece test performansı ve kararsız testler hakkında Tuist kontrol panelinde doğrudan görünürlük elde edersiniz.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixir ile başlayın</.localized_link> kılavuzunu tamamlayın

## Test çalıştırmalarınızı bildirin {#report-your-test-runs}

Paylaşılan kurulum, test entegrasyonunu yükler. Aynı bağımsız değişkenler, çıktı ve çıkış koduyla `mix test` kullanmaya devam edin:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist, çalışma tamamlandığında bildirimi gönderir; ek bir test takma adına gerek yoktur.

Test içgörülerinize Tuist kontrol panelinden erişebilir ve zaman içindeki değişimlerini görebilirsiniz:

![Bir Phoenix uygulamasının test kontrol paneli](/images/guides/features/elixir/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Paket, ExUnit sonuçlarını toplar; bunlar şunları içerir:
- Her bir testin geç/kalma durumu ve süresi
- Her testin ait olduğu modül ve `describe` bloğu
- Her hata için mesaj ve konum
- Çalıştırmalar arasında kararsız test algılama
- Dal ve commit; sürekli entegrasyonda sağlayıcı ve çalıştırma
- Sürekli entegrasyonda, checkout'un [Git geçmişini](#git-history)

Doctest'ler diğer testler gibi raporlanır. `--cover` ile birlikte, çalıştırmanın satır kapsamı da yüklenir: bkz. <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir kod kapsamı</.localized_link>.

> [!NOTE]
> Paket, zaten kullandığınız biçimlendiricilerin yanına eklediği bir ExUnit biçimlendirici aracılığıyla raporlama yapar. Komut satırında `--formatter` belirtirseniz Mix tüm listeyi değiştirir; bu nedenle çalıştırma raporlanmaz ve görev sizi bu konuda uyarır.

### Git geçmişi {#git-history}

Sürekli entegrasyonda paket ayrıca checkout'un commit geçmişini de yükler: commit SHA'leri, ebeveynleri, commit tarihleri ve çalıştırmanın ile çekme isteğinin temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist'e varsayılan dalınıza hangi commit'lerin geldiğini söyler; örneğin bir birleştirme kuyruğunun test ettiği commit'ler. Paket, checkout'un zaten sahip olduğu geçmişi okur ve checkout temel dala sahip olmadığında en son commit'i uzak depodan ister (`git ls-remote`). Kod kapsamı dışında (`--cover`), geçmiş getirilmez. Kod kapsamı etkinse, dosya içerikleri olmadan sığ bir checkout derinleştirilir; böylece bir çekme isteğinin nerede dallandığı bulunur ve sürekli entegrasyonda Tuist'in zaten sahip olduğu commit'lere ulaşılır; bu sayede bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak depo ile iletişim kurmaz. |

## Sorun giderme {#troubleshooting}

Raporlama, testlerinizin sonucunu hiçbir zaman değiştirmez: rapor gönderilemediğinde çalıştırma normalde çıkacağı şekilde çıkar ve hiçbir şey yazdırılmaz. Bir raporun neden gönderilmediğini görmek için `TUIST_DEBUG=1` ayarlayın:

```bash
TUIST_DEBUG=1 mix test
```
