---
{
  "title": "Test Analizleri",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Analizleri ile Xcode, Gradle, Bazel, Elixir, Rust ve Once projelerindeki kararsız ve yavaş testleri tespit edin."
}
---
# Test İçgörüleri {#test-insights}

Yavaş testleri belirleyerek, kararsız testleri izleyerek ve başarısız CI çalıştırmalarını hızlıca anlayarak test paketinizin sağlığını izlemek için Test İçgörülerini kullanın. Şu anda Xcode, Gradle, Bazel, Elixir, Rust ve Once desteklenmektedir. Mevcut sonuçlar ve zamanlamalar runner'ınıza bağlıdır. Desteklenen derleme sistemlerinde testlerinizin hangi kodu yürüttüğünü takip etmek için <.localized_link href="/guides/features/test-code-coverage">Kod Kapsamı</.localized_link> bölümüne bakın. [yavaş testler](https://tuist.dev/solutions/slow-tests) ve [kararsız testler](https://tuist.dev/solutions/flaky-tests) hakkında rehberlik için çözüm kılavuzlarına bakın.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Şema post-action'ları ve Tuist CLI kullanarak Xcode test analizlerini izleyin."
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle eklentisi ile Gradle test analizlerini izleyin."
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Testleri tuist bazel test komutuyla çalıştırarak Bazel test analizlerini izleyin."
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex paketi ile Elixir projenizin testlerini izleyin."
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo test sonuçlarını, paket sürelerini ve doctest'leri alışılmış test komutunuzla izleyin."
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Once'un yerel entegrasyonu aracılığıyla bildirilen test hedeflerini, paketlerini, vakalarını, hatalarını ve yeniden deneme girişimlerini izleyin."
    link="/guides/features/test-insights/once"
/>
</.home_cards>
