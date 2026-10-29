---
{
  "title": "Install the Gradle plugin",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Gradle plugin in your project."
}
---
# Gradle პლაგინის ინსტალაცია {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგივლით პლაგინის ინსტალაციისა და კონფიგურაციის პროცესში.

პლაგინს სჭირდება Gradle 8.12.1 ან უფრო ახალი ვერსია.

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

ბრძანება გაგივლით ავტორიზაციის, Tuist პროექტის შექმნის ან არჩევის და თქვენი Gradle პროექტისთვის კონფიგურაციის გენერირების პროცესში.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის გაშვების შემდეგ, თქვენ უნდა დაამატოთ Tuist პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც ეს მითითებულია ბრძანების გამოტანაში:

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გაწვდით ადგილობრივ ავტორიზაციას, თქვენს გუნდის წევრებს და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებს ცალ-ცალკე ავტორიზაცია დასჭირდებათ.

თითოეულმა გუნდის წევრმა უნდა შეასრულოს შემდეგი, რათა მიიღოს წვდომა Tuist ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ თვითმასპინძელ ან ადგილობრივ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც მითითებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი მართლწერა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატიზებული გამშვებისთვის, მიჰყევით <.localized_link href="/guides/integrations/continuous-integration#authentication">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენი გარემოსთვის.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარდაჭერს Gradle-ის კონფიგურაციის ქეშს და [იზოლირებულ პროექტებს](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; თქვენ არ გჭირდებათ მისი ცალ-ცალკე გამოყენება თითოეული ქვეპროექტისთვის.

Tuist არ რთავს ამ ფუნქციებს ავტომატურად. ოპტიმალური ჩართვისთვის, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარდაუჭირონ ეს ფუნქციები. Gradle აცხადებს თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის მითითებული, ნაგულისხმევად იღებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | უნდა აიტვირთოს თუ არა ბილდისა და ტესტის ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმევი), ატვირთვები მიმდინარეობს ფონურ რეჟიმში ადგილობრივი ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა უშვებს ტესტის შემთხვევებს, რომლებსაც ბილდი ამატებს და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურია; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |

ადგილობრივი სერვერისთვის, რომელიც იყენებს `http://` URL-ს, დაუშვით არაუსაფრთხო პროტოკოლი მხოლოდ ამ ადგილობრივ კონფიგურაციაში:

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
> `project`-ის (და არასავალდებულოდ `url`-ის) კონფიგურაციის რეკომენდებული გზა არის `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ძირითად დირექტორიაში. ამ გზით კონფიგურაცია გაზიარებულია Tuist ბრძანების ხაზის ინტერფეისსა და Gradle პლაგინს შორის. თქვენ მაინც შეგიძლიათ გადააწეროთ ეს მნიშვნელობები `settings.gradle.kts`-ში, საჭიროების შემთხვევაში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეში</.localized_link> ბილდის არტეფაქტების გასაზიარებლად თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებებზე.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link> ამოცანების დროისა და ქეშის ქცევის თვალყურის დევნისთვის Tuist დაშბორდზე.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტის ანალიტიკა</.localized_link> ტესტის შესრულების თვალყურის დევნისა და არასტაბილური ტესტების აღმოჩენისთვის.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link> არასტაბილური ტესტების ავტომატურად აღმოსაჩენად, თვალყურის სადევნებლად და იზოლირებისთვის.
