---
{
  "title": "Elixir Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını izlemek için Elixir projenizin testlerini Tuist panosunda takip edin."
}
---
# Elixir test içgörüleri {#elixir-test-insights}

Tuist'in Hex paketi, her test çalıştırmasından sonra Elixir projenizin test sonuçlarını yükler ve Tuist panosunda doğrudan test performansı ile kararsız testler hakkında görünürlük sağlar.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/elixir-project">Elixir ile başlayın</.localized_link> kılavuzunu tamamlayın

## Test çalışmalarınızı bildirin {#report-your-test-runs}

Paylaşılan kurulum, test entegrasyonunu yükler. Aynı bağımsız değişkenler, çıktı ve çıkış koduyla `mix test` kullanmaya devam edin:

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist, çalışma tamamlandığında bildirimi gönderir; ek bir test takma adına gerek yoktur.

Test içgörülerinize Tuist panosundan erişebilir ve zaman içindeki gelişimini takip edebilirsiniz:

![Bir Phoenix uygulamasının test panosu](/images/guides/features/elixir/tests-dashboard.png)

## Neler izlenir {#what-is-tracked}

Paket, ExUnit sonuçlarını toplar; bunlar şunları içerir:
- Tekil testlerin geçme/kalma durumu ve süresi
- Her testin ait olduğu modül ve `describe` bloğu
- Her başarısızlığın mesajı ve konumu
- Çalıştırmalar arasında kararsız test tespiti
- Dal ve commit bilgisi; sürekli entegrasyonda sağlayıcı ve çalışma
- Sürekli entegrasyonda, checkout'un [Git geçmişini](#git-history)

Doctest'ler diğer testler gibi raporlanır. `--cover` ile birlikte, çalışmanın satır kapsamı da yüklenir: bkz. <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir kod kapsamı</.localized_link>.

> [!NOTE]
> Paket, zaten kullandığınız biçimlendiricilerin yanına eklediği bir ExUnit biçimlendirici aracılığıyla raporlama yapar. Komut satırında `--formatter` belirtirseniz Mix tüm listeyi değiştirir; bu nedenle çalışma raporlanmaz ve görev sizi bu konuda uyarır.

### Git geçmişi {#git-history}

Sürekli entegrasyonda paket ayrıca checkout'un commit geçmişini de yükler: commit SHA'leri, ebeveynleri, commit tarihleri ve çalışmanın ile pull request'in temel dalının bulunduğu dal. Dosya içerikleri, commit mesajları veya yazarlar yüklenmez. Bu bilgiler, Tuist'e hangi commit'lerin varsayılan dalınıza geldiğini söyler; örneğin birleştirme kuyruğunun test ettiği commit'ler. Paket, checkout'ta zaten bulunan geçmişi okur ve checkout temel dala sahip değilse uzaktan en son commit'i ister (`git ls-remote`). Kod kapsamı dışında (`--cover`), geçmiş getirilmez. Kod kapsamı etkin olduğunda, dosya içerikleri olmadan sığ bir checkout derinleştirilir; böylece pull request'in ayrıldığı nokta bulunur ve sürekli entegrasyonda Tuist'in zaten sahip olduğu commit'lere ulaşılır. Bu sayede bir commit, üzerinde durduğu ebeveyni olmadan asla yüklenmez.

| Değişken | Etki |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Hiçbir Git geçmişini okumaz veya yüklemez. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Yalnızca checkout'u okur, uzak sunucuyla iletişim kurmaz. |

## Sorun giderme {#troubleshooting}

Raporlama, testlerinizin sonucunu asla değiştirmez: Rapor gönderilemezse çalışma normal şekilde sonlanır ve hiçbir şey yazdırılmaz. Bir raporun neden gönderilmediğini görmek için `TUIST_DEBUG=1` ayarlayın:

```bash
TUIST_DEBUG=1 mix test
```
