---
{
  "title": "Gradle-ის პლაგინის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და კონფიგურაციით მოარგოთ Tuist-ის Gradle-ის პლაგინი თქვენს პროექტში."
}
---
# Gradle პლაგინის ინსტალაცია {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდების ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდების ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ მიმოხილვას პლაგინის ინსტალაციისა და კონფიგურაციის შესახებ.

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

`tuist init`-ის გაშვების შემდეგ, თქვენ უნდა დაამატოთ Tuist პლაგინი თქვენს `settings.gradle.kts`-ში, როგორც მითითებულია ბრძანების გამომავალ მონაცემებში:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გაძლევთ ავტორიზაციას ლოკალურად, თქვენს გუნდის წევრებს და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებს ცალ-ცალკე ავტორიზაცია დასჭირდებათ.

თითოეულმა გუნდის წევრმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, გადაეცით იგივე საბაზისო URL, რომელიც კონფიგურირებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი წერა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განსხვავდება `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატიზებული გამშვებლებისთვის, მიჰყევით <.localized_link href="/guides/server/authentication#continuous-integration">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენს გარემოში.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარდაჭერილია Gradle-ის კონფიგურაციის ქეშით და [იზოლირებული პროექტებით](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეულ ქვეპროექტზე.

Tuist არ ააქტიურებს ამ ფუნქციებს ავტომატურად. ოპტიმიზაციისთვის, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle აცნობებს თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## პრევიუების გამოქვეყნება {#publish-previews}

Android აპლიკაციის მოდულებისთვის, პლაგინი რეგისტრირებს `tuistShare<Variant>` ამოცანებს:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ამოცანა აგებს და ამოწმებს ერთ ხელმოწერილ APK-ს, შემდეგ აქვეყნებს მას თქვენი არსებული Tuist ავტორიზაციით. ამოცანის გამოძახება არის ოპტ-ინი: ჩვეულებრივი `assemble`, `build` და ტესტის ამოცანები არ აქვეყნებენ პრევიუებს. CLI ატვირთვის ნაბიჯი არ არის საჭირო. იხილეთ <.localized_link href="/guides/features/previews/gradle">Gradle პრევიუები</.localized_link> უფლებამოსილების, ქეშის აღდგენისა და შეცდომების ქცევის შესახებ.

## კონფიგურაციის მითითება {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist` გაფართოების ბლოკში `settings.gradle.kts`-ში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის დაყენებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის საბაზისო URL. თუ არ არის დაყენებული, ნაგულისხმევად იღებს `"https://tuist.dev"` ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | ატვირთოს თუ არა ბილდისა და ტესტის ანალიტიკა ფონურ რეჟიმში. როდესაც `null` (ნაგულისხმევი), ატვირთვები მიმდინარეობს ფონურ რეჟიმში ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებლებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა ატარებს ტესტის შემთხვევებს, რომლებიც ბილდმა დაამატა და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურია; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების სტრეს-ტესტირება</.localized_link>. გამორთულია, თუ არ არის დაყენებული. |

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
> `project`-ის (და არასავალდებულოდ `url`-ის) კონფიგურაციის რეკომენდებული გზა არის `tuist.toml` ფაილი თქვენი პროექტის ძირითად საქაღალდეში. ამ გზით კონფიგურაცია იზიარება Tuist ბრძანების ხაზის ინტერფეისსა და Gradle პლაგინს შორის. თუ საჭიროა, მაინც შეგიძლიათ გადააწყოთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის დაყენებისა და კონფიგურაციის შემდეგ შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">დაშორებული ბილდის ქეში</.localized_link>, რათა გაუზიაროთ ბილდის არტიფაქტები თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებლებს.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>, რათა Tuist დაფაზე დააკვირდეთ ამოცანების შესრულების დროს და ქეშის ქცევას.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტის ანალიტიკა</.localized_link>, რათა დააკვირდეთ ტესტების წარმადობას და აღმოაჩინოთ არასტაბილური ტესტები.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link>, რათა ავტომატურად აღმოაჩინოთ, დააკვირდეთ და იზოლიროთ არასტაბილური ტესტები.
