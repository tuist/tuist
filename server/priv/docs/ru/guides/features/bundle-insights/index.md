---
{
  "title": "Аналитика размеров бандлов",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте размер iOS- и Android-бандлов, выявляйте регрессии до релиза и сохраняйте приложение компактным с помощью аналитики размеров бандлов в Tuist."
}
---
# Аналитика бандлов {#bundle-insights}

По мере добавления новых возможностей в приложение размер бандла растёт. Часть этого роста неизбежна, но многое можно избежать: дублирующиеся ресурсы, неиспользуемые символы и платформенно-специфичный мусор накапливаются. Tuist Bundle Insights поддерживает бандлы как для **Apple**, так и для **Android**, предоставляя инструменты и аналитику, которые помогают сохранять размер приложения небольшим, и отслеживает динамику во времени.

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
