---
{
  "title": "Gradle პლაგინის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და კონფიგურაციოთ Tuist-ის Gradle პლაგინი თქვენს პროექტში."
}
---
# Gradle პლაგინის ინსტალაცია {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle პროექტში ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ დეტალურ ინსტრუქციას პლაგინის ინსტალაციისა და კონფიგურაციის შესახებ.

პლაგინი მოითხოვს Gradle 8.12.1 ან უფრო ახალ ვერსიას.

## 1. Tuist-ის ინიციალიზაცია {#initialize-tuist}

შეასრულეთ შემდეგი ბრძანება თქვენი Gradle პროექტის ძირითად დირექტორიაში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება მიგიყვანთ ავტორიზაციის, Tuist პროექტის შექმნის ან არჩევისა და თქვენი Gradle პროექტისთვის კონფიგურაციის გენერირების პროცესში.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის გაშვების შემდეგ, თქვენ უნდა დაამატოთ Tuist პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც მითითებულია ბრძანების შეტყობინებაში:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` ავტორიზაციას ახდენს ლოკალურად, თქვენმა თანაგუნდელებმა და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებმა ცალ-ცალკე უნდა გაიარონ ავტორიზაცია.

ყოველმა თანაგუნდელმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც მითითებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი დაწერილობა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განსხვავდება `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატიზებული გამშვებისთვის (runners) მიჰყევით <.localized_link href="/guides/integrations/continuous-integration#authentication">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენი გარემოსთვის.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარს უჭერს Gradle-ის კონფიგურაციის ქეშს და [იზოლირებულ პროექტებს](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეული ქვეპროექტისთვის.

Tuist არ რთავს ამ ფუნქციებს ავტომატურად. ჩასართავად დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle აცხადებს თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## პრევიუსების გამოქვეყნება {#publish-previews}

Android აპლიკაციის მოდულებისთვის პლაგინი რეგისტრირებს `tuistShare<Variant>` ტასკებს:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ტასკი აგებს და ამოწმებს ერთ ხელმოწერილ APK-ს, შემდეგ კი აქვეყნებს მას თქვენი არსებული Tuist ავტორიზაციით. ტასკის გამოძახება ნიშნავს ჩართვას: ჩვეულებრივი `assemble`, `build` და ტესტის ტასკები არ აქვეყნებენ პრევიუსებს. CLI-ით ატვირთვის ეტაპი არ არის საჭირო. იხილეთ <.localized_link href="/guides/features/previews/gradle">Gradle პრევიუსები</.localized_link> შესაბამისობის, ქეშის განმეორებითი გამოყენებისა და შეცდომების ქცევის შესახებ.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის მითითებული, ნაგულისხმევად იღებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | ატვირთოს თუ არა ბილდისა და ტესტების ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმევი), ატვირთვა ხდება ფონურ რეჟიმში ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებებზე (runners). |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა უშვებს ტესტის შემთხვევებს, რომლებიც ბილდმა დაამატა და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურად აღმოჩნდება; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |

ლოკალური სერვერისთვის, რომელიც იყენებს `http://` URL-ს, დაუშვით არაუსაფრთხო პროტოკოლი მხოლოდ ამ ლოკალურ კონფიგურაციაში:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

არ ჩართოთ `allowInsecureProtocol` ჰოსტინგული ან სხვა `https://` სერვერებისთვის.

> [!NOTE]
> **Tuist.toml**
>
> `project`-ის (და სურვილისამებრ `url`-ის) კონფიგურირების რეკომენდებული გზაა `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ძირში. ამ გზით კონფიგურაცია გაზიარებულია Tuist-ის ბრძანების სტრიქონის ინტერფეისსა და Gradle პლაგინს შორის. საჭიროების შემთხვევაში, შეგიძლიათ გადაწეროთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის დაყენებისა და კონფიგურირების შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">შორეული ბილდის ქეში</.localized_link> ბილდის არტეფაქტების გასაზიარებლად თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებებს (runners) შორის.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link> ამოცანების შესრულების დროისა და ქეშის ქცევის თვალყურის სადევნებლად Tuist-ის დაფაზე.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტების ანალიტიკა</.localized_link> ტესტების წარმადობის თვალყურის სადევნებლად და არასტაბილური ტესტების აღმოსაჩენად.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link> არასტაბილური ტესტების ავტომატურად აღმოსაჩენად, თვალყურის სადევნებლად და იზოლირებისთვის.
