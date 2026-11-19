---
{
  "title": "Аналитика размера бандла",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте размер iOS- и Android-бандлов, выявляйте регрессии до релиза и поддерживайте компактность приложения с помощью аналитики размера бандла в Tuist."
}
---
# Анализ размера бандла {#bundle-insights}

По мере добавления новых возможностей в приложение размер бандла увеличивается. Часть этого роста неизбежна, но многое можно предотвратить: дублирующиеся ресурсы, неиспользуемые символы и платформенно-специфичный избыточный вес накапливаются. Tuist Bundle Insights поддерживает как **Apple**, так и **Android**-бандлы, предоставляя инструменты и аналитику для поддержания небольшого размера приложения и отслеживая динамику во времени.

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
