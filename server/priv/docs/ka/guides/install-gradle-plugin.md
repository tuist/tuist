---
{
  "title": "Gradle პლაგინის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და კონფიგურირება გაუკეთოთ Tuist-ის Gradle პლაგინს თქვენს პროექტში."
}
---
# Gradle-ის პლაგინის დაყენება {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle-ის პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle-ის პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ მიმოხილვას პლაგინის დაყენებისა და კონფიგურაციის შესახებ.

პლაგინს სჭირდება Gradle 8.12.1 ან უფრო ახალი ვერსია.

## 1. Tuist-ის ინიციალიზაცია {#initialize-tuist}

შეასრულეთ შემდეგი ბრძანება თქვენი Gradle-ის პროექტის ძირითად საქაღალდეში:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

ბრძანება გაგივლით ავტორიზაციის, Tuist-ის პროექტის შექმნის ან შერჩევისა და თქვენი Gradle-ის პროექტისთვის კონფიგურაციის გენერირების პროცესში.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის გაშვების შემდეგ, თქვენ უნდა დაამატოთ Tuist-ის პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც ეს მითითებულია ბრძანების შედეგებში:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გადის ლოკალურ ავტორიზაციას, თქვენმა თანაგუნდელებმა და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებმა ცალ-ცალკე უნდა გაიარონ ავტორიზაცია.

ყოველმა თანაგუნდელმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ საკუთარ ან ლოკალურ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც მითითებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი დაწერა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განსხვავდება `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატური გამშვებებისთვის, მიჰყევით <.localized_link href="/guides/server/authentication#continuous-integration">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენს გარემოში.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარდაჭერილია Gradle-ის კონფიგურაციის ქეშით და [იზოლირებული პროექტებით](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეული ქვეპროექტისთვის.

Tuist არ რთავს ამ ფუნქციებს ავტომატურად. მათ ჩასართავად, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle იტყობინება თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## პრივიუების გამოქვეყნება {#publish-previews}

Android-ის აპლიკაციის მოდულებისთვის, პლაგინი არეგისტრირებს `tuistShare<Variant>` ამოცანებს:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ამოცანა აგებს და ამოწმებს ერთ ხელმოწერილ APK-ს, შემდეგ კი აქვეყნებს მას თქვენი არსებული Tuist ავტორიზაციით. ამოცანის გამოძახება არის ჩართვის მექანიზმი: ჩვეულებრივი `assemble`, `build` და ტესტის ამოცანები არ აქვეყნებენ პრივიუებს. CLI-ის ატვირთვის ეტაპი არ არის საჭირო. იხილეთ <.localized_link href="/guides/features/previews/gradle">Gradle პრივიუები</.localized_link> შესაბამისობის, ქეშის აღდგენისა და შეცდომების ქცევის შესახებ.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის მითითებული, ნაგულისხმევად იღებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | ატვირთოს თუ არა ბილდისა და ტესტის ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმევი), ატვირთვები მიმდინარეობს ფონურ რეჟიმში ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა ატარებს ტესტის შემთხვევებს, რომლებიც ბილდმა დაამატა და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურია; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |

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
> `project`-ის (და სურვილისამებრ `url`-ის) კონფიგურაციის რეკომენდებული გზა არის `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ძირითად საქაღალდეში. ამ გზით კონფიგურაცია გაზიარებულია Tuist-ის ბრძანების სტრიქონის ინტერფეისსა და Gradle-ის პლაგინს შორის. საჭიროების შემთხვევაში, შეგიძლიათ გადააწეროთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს ატარებს HTTP პროქსის მეშვეობით, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">დაშორებული ბილდის ქეში</.localized_link>, რათა გაუზიაროთ ბილდის არტეფაქტები თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებებს.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>, რათა Tuist-ის დაფაზე თვალი ადევნოთ ამოცანების შესრულების დროსა და ქეშის ქცევას.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტის ანალიტიკა</.localized_link>, რათა თვალი ადევნოთ ტესტების წარმადობას და აღმოაჩინოთ არასტაბილური ტესტები.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link>, რათა ავტომატურად აღმოაჩინოთ, თვალი ადევნოთ და იზოლირება მოახდინოთ არასტაბილური ტესტების.
