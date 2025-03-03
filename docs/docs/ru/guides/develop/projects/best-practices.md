---
title: Лучшие практики
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Узнайте о лучших практиках работы с Tuist и проектами Xcode.
---

# Лучшие практики

На протяжении многих лет работы с различными командами и проектами мы выявили набор лучших практик, которые мы рекомендуем соблюдать при работе с Tuist и проектами Xcode. Эти практики не являются обязательными, но они могут помочь вам структурировать ваши проекты таким образом, чтобы их было проще поддерживать и масштабировать.

## Xcode {#xcode}

### Нерекомендуемые паттерны {#discouraged-patterns}

#### Конфигурации для моделирования удаленных сред {#configurations-to-model-remote-environments}

Многие организации используют конфигурации сборки для моделирования различных удаленных сред (например, `Debug-Production` или `Release-Canary`), но у этого подхода есть некоторые недостатки:

- **Несоответствия:** Если в графе сборки имеются конфигурационные несоответствия, система сборки может в итоге использовать неправильную конфигурацию для некоторых тергитов.
- **Сложность:** Проекты могут иметь большой список локальных конфигураций и удаленных сред, которые сложно анализировать и поддерживать.

Конфигурации сборки изначально предназначены для представления различных настроек сборки, и проектам редко требуется больше, чем просто `Debug` и `Release`. Необходимость моделировать различные среды может быть удовлетворена с помощью схем:

- **In Debug builds:** You can include all the configurations that should be accessible in development in the app (e.g. endpoints), and switch them at runtime. The switch can happen either using scheme launch environment variables, or with a UI within the app.
- **In Release builds:** In case of release, you can only include the configuration that the release build is bound to, and not include the runtime logic for switching configurations by using compiler directives.
