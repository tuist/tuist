---
{
  "title": "Kararsız Testler",
  "titleTemplate": ":title · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "CI boru hatlarınızda kararsız testleri otomatik olarak tespit edin ve izleyin."
}
---
# Kararsız Testler {#flaky-tests}

Kararsız testler, aynı kodla birden fazla kez çalıştırıldığında farklı sonuçlar (başarılı veya başarısız) üreten testlerdir. Test paketinize olan güveni zedeler ve geliştiricilerin yanlış hataları araştırması için zaman kaybına neden olur. Tuist, kararsız testleri otomatik olarak algılar ve bunları zaman içinde takip etmenize yardımcı olur.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test aracılığıyla Xcode projelerindeki kararsız testleri algılayın, yönetin ve karantinaya alın."
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="tuist test aracılığıyla Tuist tarafından oluşturulan projelerdeki kararsız testleri algılayın, yönetin ve karantinaya alın."
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle projelerindeki kararsız testleri algılayın ve yönetin."
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test aracılığıyla kararsız Bazel test senaryolarını algılayın, sessize alın ve atlayın."
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="Test yeniden denemeleri ile Elixir projelerindeki kararsız testleri algılayın ve yönetin."
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="CI çalıştırmaları genelindeki sonuçları kullanarak kararsız Cargo testlerini algılayın ve inceleyin."
    link="/guides/features/test-insights/flaky-tests/rust"
/>
  <.home_card
    title="Once"
    details="Raporlanan yeniden deneme girişimleri ve CI geçmişi aracılığıyla tutarsız test sonuçlarını inceleyin."
    link="/guides/features/test-insights/flaky-tests/once"
/>
</.home_cards>
