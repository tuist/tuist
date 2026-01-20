---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# التكامل المستمر (CI) {#continuous-integration-ci}

لتشغيل أوامر Tuist في عمليات سير عمل [التكامل المستمر]
(https://en.wikipedia.org/wiki/Continuous_integration) الخاصة بك، ستحتاج إلى
تثبيته في بيئة CI الخاصة بك.

تكون المصادقة اختيارية ولكنها مطلوبة إذا كنت تريد استخدام ميزات من جانب الخادم مثل <LocalizedLink href="/guides/features/cache">ذاكرة التخزين المؤقت</LocalizedLink>.

تقدم الأقسام التالية أمثلة على كيفية القيام بذلك على منصات CI المختلفة.

## أمثلة {#examples}

### إجراءات GitHub {#github-actions}

في [إجراءات GitHub](https://docs.github.com/en/actions) يمكنك استخدام مصادقة
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC</LocalizedLink>
للمصادقة الآمنة وغير السرية:

:::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Project token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Project token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```

::::

::: info OIDC SETUP
قبل استخدام مصادقة OIDC، تحتاج إلى <LocalizedLink href="/guides/integrations/gitforge/github">ربط مستودع GitHub الخاص بك</LocalizedLink> بمشروعك Tuist. الأذونات `: الرمز المميز للمعرف: الكتابة` مطلوب لكي يعمل OIDC. وبدلاً من ذلك، يمكنك استخدام <LocalizedLink href="/guides/server/authentication#project-tokens">رمز المشروع</LocalizedLink> مع `TUIST_TOKEN` السري.
:::

::: tip
نوصي باستخدام `mise استخدام --pin` في مشاريع تويست الخاصة بك لتثبيت إصدار تويست
عبر البيئات. سينشئ الأمر ملف `.tool-versions` يحتوي على إصدار تويست.
:::

### سحابة Xcode السحابية {#xcode-cloud}

في [Xcode Cloud] (https://developer.apple.com/xcode-cloud/)، الذي يستخدم مشاريع
Xcode كمصدر للحقيقة، ستحتاج إلى إضافة [ما بعد الاستنساخ]
(https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
برنامج نصي لتثبيت Tuist وتشغيل الأوامر التي تحتاجها، على سبيل المثال `tuist
توليد`:

:::: مجموعة الرموز

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
استخدم رمزًا مميزًا
<LocalizedLink href="/guides/server/authentication#project-tokens"> للمشروع
</LocalizedLink> عن طريق تعيين متغير البيئة `TUIST_TOKEN` في إعدادات سير عمل
Xcode Cloud الخاص بك.
<!-- -->
:::

### سيركلسي {#circleci}

في [CircleCI](https://circleci.com) يمكنك استخدام مصادقة
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC</LocalizedLink>
للمصادقة الآمنة وغير السرية:

:::: مجموعة الرموز
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
قبل استخدام مصادقة OIDC، تحتاج إلى
<LocalizedLink href="/guides/integrations/gitforge/github"> ربط مستودع GitHub
الخاص بك </LocalizedLink> بمستودع GitHub الخاص بك بمشروع Tuist الخاص بك. تتضمن
رموز CircleCI OIDC الرموز المميزة لمستودع GitHub المتصل الخاص بك، والتي يستخدمها
Tuist لتخويل الوصول إلى مشاريعك. بدلاً من ذلك، يمكنك استخدام
<LocalizedLink href="/guides/server/authentication#project-tokens"> رمز المشروع
المميز</LocalizedLink> مع متغير البيئة `TUIST_TOKEN`.
<!-- -->
:::

### بيترايز {#bitrise}

على [Bitrise](https://bitrise.io) يمكنك استخدام مصادقة
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC</LocalizedLink>
للمصادقة الآمنة وغير السرية:

:::: مجموعة الرموز
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
قبل استخدام مصادقة OIDC، تحتاج إلى
<LocalizedLink href="/guides/integrations/gitforge/github"> ربط مستودع GitHub
الخاص بك </LocalizedLink> بمستودع GitHub الخاص بك بمشروع Tuist الخاص بك. تتضمن
رموز Bitrise OIDC الرموز المميزة لمستودع GitHub المتصل الخاص بك، والذي يستخدمه
Tuist لتخويل الوصول إلى مشاريعك. بدلاً من ذلك، يمكنك استخدام
<LocalizedLink href="/guides/server/authentication#project-tokens"> رمز المشروع
المميز</LocalizedLink> مع متغير البيئة `TUIST_TOKEN`.
<!-- -->
:::

### كودماغك {#codemagic}

في [Codemagic] (https://codemagic.io)، يمكنك إضافة خطوة إضافية إلى سير عملك
لتثبيت Tuist:

:::: مجموعة الرموز
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
قم بإنشاء <LocalizedLink href="/guides/server/authentication#project-tokens">رمز
مميز </LocalizedLink> للمشروع وأضفه كمتغير بيئة سري باسم `TUIST_TOKEN`.
<!-- -->
:::
