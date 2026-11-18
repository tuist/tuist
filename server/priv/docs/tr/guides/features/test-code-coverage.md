---
{
  "title": "Kod Kapsamı",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Test çalıştırmalarınızdan her dosyanın ve commit'in satır kapsamını takip edin."
}
---
# Kod Kapsamı {#code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her test çalıştırmasının kapsamını yükler ve bir commit'in çalıştırmalarını dosya başına ve tüm proje genelinde tek bir rakamda birleştirir; böylece dashboard üzerinde commit commit takip edebilirsiniz.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test ile test edilen Xcode projelerinin kod kapsamını yükleyin."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist tarafından oluşturulan projelerde kod kapsamını tuist test, ikili önbellek ve seçici test ile ölçün."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="mix test --cover ile test edilen Elixir projelerinin satır kapsamını yükleyin."
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="cargo test ile test edilen Rust projelerinin satır kapsamını yükleyin."
    link="/guides/features/test-code-coverage/rust"
/>
  <.home_card
    title="Gradle"
    details="Her testin hangi dosyaları çalıştırdığı bilgisiyle birlikte Gradle projelerinin kod kapsamını yükleyin."
    link="/guides/features/test-code-coverage/gradle"
/>
</.home_cards>
