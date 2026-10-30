---
{
  "title": "Gradle პლაგინის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და კონფიგურირება გაუკეთოთ Tuist-ის Gradle პლაგინს თქვენს პროექტში."
}
---
# Gradle პლაგინის დაყენება {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">შორეული ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგივლით პლაგინის დაყენებისა და კონფიგურაციის პროცესში.

პლაგინს სჭირდება Gradle 8.12.1 ან უფრო ახალი ვერსია.

## 1. Tuist-ის ინიციალიზაცია {#initialize-tuist}

შეასრულეთ შემდეგი ბრძანება თქვენი Gradle პროექტის ძირითად საქაღალდეში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება გაგივლით ავტორიზაციის, Tuist პროექტის შექმნის ან არჩევის და თქვენი Gradle პროექტისთვის კონფიგურაციის გენერირების პროცესში.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის გაშვების შემდეგ, თქვენ უნდა დაამატოთ Tuist პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც მითითებულია ბრძანების შედეგებში:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გადის ლოკალურ ავტორიზაციას, თქვენმა თანაგუნდელებმა და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებმა ცალ-ცალკე უნდა გაიარონ ავტორიზაცია.

თითოეულმა თანაგუნდელმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ საკუთარ ადგილზე განთავსებულ ან ლოკალურ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც მითითებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი მართლწერა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატიზებული გამშვებლებისთვის, მიჰყევით <.localized_link href="/guides/integrations/continuous-integration#authentication">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენს გარემოში.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარს უჭერს Gradle-ის კონფიგურაციის ქეშს და [იზოლირებულ პროექტებს](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეულ ქვეპროექტზე.

Tuist არ ააქტიურებს ამ ფუნქციებს ავტომატურად. ოპტიმიზაციისთვის, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle აცხადებს თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმები | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის მითითებული, ნაგულისხმევად იყენებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | უნდა აიტვირთოს თუ არა ბილდისა და ტესტების ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმები), ატვირთვები მიმდინარეობს ფონურ რეჟიმში ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებლებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა უშვებს ტესტების შემთხვევებს, რომლებიც ბილდმა დაამატა და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურად აღმოჩნდება; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |

ლოკალური სერვერისთვის, რომელიც იყენებს `http://` URL-ს, დაუშვით არაუსაფრთხო პროტოკოლი მხოლოდ ამ ლოკალურ კონფიგურაციაში:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

არ ჩართოთ `allowInsecureProtocol` ჰოსტინგის ან სხვა `https://` სერვერებისთვის.

> [!NOTE]
> **Tuist.toml**
>
> რეკომენდებული გზა `project`-ის (და არასავალდებულოდ `url`-ის) კონფიგურაციისთვის არის `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ძირითად საქაღალდეში. ამ გზით კონფიგურაცია გაზიარებულია Tuist ბრძანების ხაზის ინტერფეისსა და Gradle პლაგინს შორის. თუ საჭიროა, შეგიძლიათ გადააწეროთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს ატარებს HTTP პროქსის მეშვეობით, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის დაყენებისა და კონფიგურაციის შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">შორეული ბილდის ქეში</.localized_link> ბილდის არტეფაქტების გასაზიარებლად თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებლებს შორის.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link> ამოცანების დროისა და ქეშის ქცევის თვალყურის დევნისთვის Tuist დაფაზე.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტების ანალიტიკა</.localized_link> ტესტების შესრულების თვალყურის დევნისა და არასტაბილური ტესტების აღმოსაჩენად.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link> არასტაბილური ტესტების ავტომატურად აღმოსაჩენად, თვალყურის დევნისა და კარანტინში მოსათავსებლად.
