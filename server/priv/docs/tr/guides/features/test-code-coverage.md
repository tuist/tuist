---
{
  "title": "Kod Kapsamı",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Test çalıştırmalarınızdan her dosyanın ve commit'in satır kapsamını takip edin."
}
---
# Kod Kapsamı {#code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her test çalıştırmasının kapsamını yükler ve bir commit'in çalıştırmalarını dosya bazında ve tüm proje için tek bir rakamda birleştirir; böylece bunu panoda commit commit takip edebilirsiniz.

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test ile test edilen Xcode projelerinin kod kapsamını yükleyin."
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist ile oluşturulan projelerde tuist test, binary cache ve seçici test kullanarak kod kapsamını ölçün."
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="mix test --cover ile test edilen Elixir projelerinin satır kapsamını yükleyin."
    link="/guides/features/test-code-coverage/elixir"
/>
</.home_cards>
