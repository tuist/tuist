---
{
  "title": "Что такое Tuist?",
  "description": "Виртуальная команда платформы для разработчиков. Инфраструктура сборки для Xcode, Gradle, Bazel, Elixir и Rust с возможностями, адаптированными под каждый инструментарий."
}
---

# Виртуальная команда платформы для разработчиков, которые выпускают обновления

**Tuist помогает командам масштабировать разработку приложений и быстрее выпускать обновления**, превращая сложность больших кодовых баз в продуктивный опыт, который растёт вместе с вашей командой. Он работает с уже используемыми вами системами сборки для проектов на Xcode, Gradle, Bazel, Elixir и Rust. Доступные возможности зависят от вашего инструментария: проекты на Rust получают аналитику сборки и тестирования Cargo, включая doctests, обнаружение нестабильных тестов и экспериментальное кэширование компиляции.

Начните с <.localized_link href="/guides/install-tuist">установки интерфейса командной строки Tuist</.localized_link>, затем выберите один из <.localized_link href="/guides/get-started">вариантов начала работы</.localized_link> для вашей системы сборки.

<br/>

<.home_cards>
  <.home_card
    title="Кэш"
    details="Делитесь результатами компиляции между членами команды и CI. Работает с кэшем компиляции Xcode, кэшем модулей Tuist, кэшем сборки Gradle, удалённым кэшем Bazel и экспериментальным кэшем компиляции Rust."
    supported_for="apple,gradle,bazel,rust"
    link="/guides/features/cache"
/>
  <.home_card
    title="Аналитика сборок и тестов"
    details="Отслеживайте длительность сборок и тестов, сбои, нестабильность и регрессии в проектах на Xcode, Gradle, Bazel, Elixir и Rust."
    supported_for="apple,gradle,bazel,elixir,rust"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="Выборочное тестирование"
    details="Запускайте только те тесты, которые затронуты изменениями, в проектах Xcode и сгенерированных проектах, чтобы обратная связь приходила за секунды."
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="Раннеры"
    details="Запускайте CI на управляемых раннерах macOS и Linux, близко к тому же кэшу, который используют машины ваших разработчиков."
    link="/guides/features/runners"
/>
  <.home_card
    title="Превью"
    details="Мгновенно делитесь приложением по ссылке. Без задержек на проверку в сторе и без сложной настройки."
    link="/guides/features/previews"
/>
  <.home_card
    title="Сгенерированные проекты"
    details="Описывайте проекты Xcode на Swift и генерируйте их согласованно. Устраните конфликты слияния и разблокируйте кэш модулей."
    link="/guides/features/projects"
/>
  <.home_card
    title="Реестр пакетов"
    details="Разрешайте зависимости Swift-пакетов за секунды вместо минут с помощью реестра, работающего на базе сети кэшей Tuist."
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="Размер бандла"
    details="Анализируйте и поддерживайте минимальный размер приложения, чтобы пользователи быстрее скачивали его, а вы соответствовали требованиям стора."
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## Нам доверяют команды, выпускающие обновления в масштабе

**Команды из [Trendyol](https://www.trendyol.com/), [Etsy](https://www.etsy.com/), [Bumble](https://bumble.com/), [Monzo](https://monzo.com/), [Bending Spoons](https://bendingspoons.com/) и более чем 100 других компаний** быстрее выпускают обновления с Tuist для своих кодовых баз iOS и Android.
