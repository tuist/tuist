---
{
  "title": "Kod Kapsamı",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Test çalıştırmalarınızdan her dosyanın ve commit'in satır kapsamını takip edin."
}
---
# Kod Kapsamı {#code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her test çalıştırmasının kapsamını yükler ve bir commit içindeki çalıştırmaları dosya bazında ve tüm proje genelinde tek bir rakamda birleştirir; böylece panoda commit commit takip edebilirsiniz.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test ile test edilen Xcode projelerinin kod kapsamını yükleyin."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist tarafından oluşturulan projelerde tuist test, binary cache ve seçici test ile kod kapsamını ölçün."
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
</.home_cards>
