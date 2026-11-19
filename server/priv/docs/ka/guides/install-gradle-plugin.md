---
{
  "title": "Gradle-ის პლაგინის დაყენება",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააყენოთ და მოარგოთ Tuist-ის Gradle-ის პლაგინი თქვენს პროექტში."
}
---
# Gradle-ის პლაგინის დაყენება {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle-ის პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle-ის პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ დახმარებას პლაგინის დაყენებასა და კონფიგურაციაში.

პლაგინს სჭირდება Gradle 8.12.1 ან უფრო ახალი ვერსია.

## 1. Tuist-ის ინიციალიზაცია {#initialize-tuist}

შეასრულეთ შემდეგი ბრძანება თქვენი Gradle-ის პროექტის ფესვში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება გაგივლით ავტორიზაციის, Tuist-ის პროექტის შექმნის ან შერჩევის და თქვენი Gradle-ის პროექტისთვის კონფიგურაციის გენერირების პროცესში.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის შესრულების შემდეგ, თქვენ უნდა დაამატოთ Tuist-ის პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც მითითებულია ბრძანების გამოტანაში:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გაავთენტებს თქვენ ლოკალურად, თქვენს გუნდის წევრებსა და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებს ცალ-ცალკე ავტორიზაცია დასჭირდებათ.

თითოეულმა გუნდის წევრმა უნდა შეასრულოს შემდეგი, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც კონფიგურირებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის მართლწერის თანმიმდევრულობა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატური გამშვებებისთვის, მიჰყევით <.localized_link href="/guides/server/authentication#continuous-integration">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენი გარემოსთვის.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარს უჭერს Gradle-ის კონფიგურაციის ქეშს და [იზოლირებულ პროექტებს](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეულ ქვეპროექტზე.

Tuist არ რთავს ამ ფუნქციებს ავტომატურად. მათ ჩასართავად, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle იუწყება თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## პრევიუების გამოქვეყნება {#publish-previews}

Android აპლიკაციის მოდულებისთვის, პლაგინი არეგისტრირებს `tuistShare<Variant>` ამოცანებს:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ამოცანა აწყობს და ამოწმებს ერთ ხელმოწერილ APK-ს, შემდეგ კი აქვეყნებს მას თქვენი არსებული Tuist ავტორიზაციით. ამოცანის გამოძახება ნიშნავს ჩართვას: ჩვეულებრივი `assemble`, `build` და ტესტირების ამოცანები არ აქვეყნებენ პრევიუებს. CLI ატვირთვის ეტაპი არ არის საჭირო. იხილეთ <.localized_link href="/guides/features/previews/gradle">Gradle პრევიუები</.localized_link> უფლებამოსილების, ქეშის აღდგენისა და შეცდომების ქცევის შესახებ.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმები | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის მითითებული, ნაგულისხმევად იყენებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | ატვირთოს თუ არა ბილდისა და ტესტების ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმები), ატვირთვები ფონურ რეჟიმში ხდება ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებლებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა უშვებს ტესტის შემთხვევებს, რომლებსაც ბილდი ამატებს და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურად აღმოჩნდება; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |

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
> `project`-ის (და სურვილისამებრ `url`-ის) კონფიგურირების რეკომენდებული გზა არის `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ფესვში. ამ გზით კონფიგურაცია საერთოა Tuist-ის ბრძანების ხაზის ინტერფეისსა და Gradle-ის პლაგინს შორის. საჭიროების შემთხვევაში, თქვენ კვლავ შეგიძლიათ გადაწეროთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის დაყენებისა და კონფიგურაციის შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">დაშორებული ბილდის ქეში</.localized_link> ბილდის არტეფაქტების გასაზიარებლად თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებლებს შორის.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link> ამოცანების შესრულების დროისა და ქეშის ქცევის თვალყურის სადევნებლად Tuist-ის დაფაზე.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტების ანალიტიკა</.localized_link> ტესტების წარმადობის თვალყურის სადევნებლად და არასტაბილური ტესტების აღმოსაჩენად.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link> არასტაბილური ტესტების ავტომატურად აღმოსაჩენად, თვალყურის სადევნებლად და იზოლირებისთვის.
