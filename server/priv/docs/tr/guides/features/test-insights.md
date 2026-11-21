---
{
  "title": "Test İçgörüleri",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test İçgörüleri ile Xcode, Gradle, Bazel, Elixir, Rust ve Struo projelerindeki kararsız ve yavaş testleri tespit edin."
}
---
# Test İçgörüleri {#test-insights}

Yavaş testleri belirleyerek, kararsız testleri takip ederek ve başarısız CI çalıştırmalarını hızlıca anlayarak test paketinizin sağlığını izlemek için Test İçgörüleri'ni kullanın. Şu anda Xcode, Gradle, Bazel, Elixir, Rust ve Struo'yu destekler. Mevcut sonuçlar ve zamanlamalar runner'ınıza bağlıdır. Desteklenen derleme sistemlerinde testlerinizin hangi kodu yürüttüğünü takip etmek için <.localized_link href="/guides/features/test-code-coverage">Kod Kapsamı</.localized_link> bölümüne bakın. [yavaş testler](https://tuist.dev/solutions/slow-tests) ve [kararsız testler](https://tuist.dev/solutions/flaky-tests) hakkında rehberlik için çözüm kılavuzlarına bakın.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Scheme post-action'ları ve Tuist CLI kullanarak Xcode test analizlerini takip edin."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle eklentisi ile Gradle test analizlerini takip edin."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test komutuyla testleri çalıştırarak Bazel test analizlerini takip edin."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex paketi ile Elixir projenizin testlerini takip edin."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo test sonuçlarını, paket sürelerini ve doctest'leri alıştığınız test komutuyla takip edin."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Struo"
    details="Struo'nun yerel entegrasyonu aracılığıyla bildirilen test hedeflerini, paketlerini, durumlarını, hatalarını ve yeniden deneme girişimlerini takip edin."
    link="/guides/features/test-insights/struo"
/>
</.home_cards>
