---
{
  "title": "Аналитика размера бандла",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте размер бандлов для iOS и Android, выявляйте регрессии до релиза и поддерживайте компактность приложения с помощью аналитики размера бандла от Tuist."
}
---
# Анализ бандлов {#bundle-insights}

По мере добавления новых возможностей в приложение размер бандла продолжает расти. Часть этого роста неизбежна, но значительную часть можно избежать: дублирующиеся ресурсы, неиспользуемые символы и платформенно-специфичный мусор накапливаются. Tuist Bundle Insights поддерживает бандлы как для **Apple**, так и для **Android**, предоставляя инструменты и аналитику, которые помогают сохранять небольшой размер приложения, и отслеживает тенденцию во времени.

<.home_cards>
  <.home_card
    title="Apple"
    details="Анализируйте бандлы .ipa, .xcarchive и .app для приложений iOS, macOS, watchOS и tvOS."
    link="/guides/features/bundle-insights/apple"
    supported_for="apple"
/>
  <.home_card
    title="Android"
    details="Анализируйте бандлы .aab и .apk для приложений Android."
    link="/guides/features/bundle-insights/android"
    supported_for="android"
/>
</.home_cards>
