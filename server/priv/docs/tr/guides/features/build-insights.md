---
{
  "title": "Derleme İçgörileri",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Derleme İçgörileri ile Xcode, Gradle, Bazel, Elixir, Rust ve Once projelerinin derleme performansını takip edin."
}
---
# Derleme Analizleri {#build-insights}

Yerel ve CI derleme performansını izlemek için Derleme Analizlerini kullanın. Şu anda Xcode, Gradle, Bazel, Elixir, Rust ve Once desteklenmektedir. Yavaş derlemeler ve artan CI maliyetlerinin adım adım incelenmesi için [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) bölümlerine bakın.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuist panosunda Xcode şema sonrası eylem sürelerini, derleme ayarlarını ve derleme meta verilerini takip edin."
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Özel şemalara sahip Tuist tarafından oluşturulan projelerde derleme analizlerini takip edin."
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle eklentisi ile Gradle görev sürelerini ve önbellek etkinliğini takip edin."
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocol aracılığıyla Bazel komut süresini, önbellek toplamlarını ve kritik yol tanılarını takip edin."
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixir projenizin derlenmesinin ne kadar sürdüğünü, uyarıları ve derlemeyi yavaşlatan dosyaları takip edin."
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLI ile Cargo komut süresini, gözlemlenen rustc çağrılarını ve derleyici tanılarını takip edin."
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="Çalıştırmaları canlı olarak izleyin ve graf eylemlerini, süreleri, hataları ve önbellek kararlarını inceleyin."
    link="/guides/features/build-insights/once"
/>
</.home_cards>
