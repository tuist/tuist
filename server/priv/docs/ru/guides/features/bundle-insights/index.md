---
{
  "title": "Аналитика бандлов",
  "titleTemplate": ":title · Возможности · Руководства · Tuist",
  "description": "Отслеживайте размер бандлов для iOS и Android, выявляйте регрессии до релиза и сохраняйте приложение компактным с помощью аналитики бандлов Tuist."
}
---
# Аналитика размера бандла {#bundle-insights}

По мере добавления новых возможностей в приложение размер бандла растёт. Часть этого роста неизбежна, но многое можно избежать: дублирующиеся ресурсы, неиспользуемые символы и платформенно-специфичный избыточный вес накапливаются. Tuist Bundle Insights поддерживает как **Apple**, так и **Android**-бандлы, предоставляя инструменты и аналитику для поддержания небольшого размера приложения, а также отслеживает динамику во времени.

<.home_cards>
  <.home_card
    title="Apple"
    details="Анализируйте .ipa-, .xcarchive- и .app-бандлы для приложений iOS, macOS, watchOS и tvOS."
    link="/guides/features/bundle-insights/apple"
    supported_for="apple"
/>
  <.home_card
    title="Android"
    details="Анализируйте .aab- и .apk-бандлы для Android-приложений."
    link="/guides/features/bundle-insights/android"
    supported_for="android"
/>
</.home_cards>
