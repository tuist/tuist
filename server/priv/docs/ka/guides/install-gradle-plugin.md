---
{
  "title": "Gradle პლაგინის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და კონფიგურაციოთ Tuist-ის Gradle პლაგინი თქვენს პროექტში."
}
---
# Gradle პლაგინის ინსტალაცია {#install-the-gradle-plugin}

Tuist გთავაზობთ Gradle პლაგინს, რომელიც ინტეგრირდება თქვენს Gradle პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/cache/gradle-cache">დისტანციური ბილდის ქეშირება</.localized_link> და <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგივლით პლაგინის ინსტალაციისა და კონფიგურაციის ეტაპებს.

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

ბრძანება გაგივლით ავტორიზაციის, Tuist პროექტის შექმნის ან არჩევის და თქვენი Gradle პროექტისთვის კონფიგურაციის გენერირების პროცესს.

## 2. პლაგინის გამოყენება {#apply-the-plugin}

`tuist init`-ის გაშვების შემდეგ, ბრძანების გამოტანილი ინსტრუქციის მიხედვით, თქვენ უნდა დაამატოთ Tuist პლაგინი თქვენს `settings.gradle.kts`-ში:

<!-- @snippet: ./_gradle-plugin-block -->

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავტორიზაცია {#authenticate}

მიუხედავად იმისა, რომ `tuist init` გადის ლოკალურ ავტორიზაციას, თქვენს გუნდის წევრებს და <.localized_link href="/guides/integrations/continuous-integration">უწყვეტი ინტეგრაციის</.localized_link> გარემოებს ცალ-ცალკე დასჭირდებათ ავტორიზაცია.

თითოეულმა გუნდის წევრმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
tuist auth login
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, გადაეცით იგივე ბაზის URL, რომელიც მითითებულია `tuist.toml`-ში:

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის ერთგვაროვანი დაწერა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განსხვავდება `127.0.0.1`-ისთვის შენახული შესვლისგან.

ავტომატიზებული გამშვებლებისთვის, მიჰყევით <.localized_link href="/guides/server/authentication#continuous-integration">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link>, რათა დააკონფიგურიროთ ავტორიზაცია თქვენს გარემოში.

## კონფიგურაციის ქეში და იზოლირებული პროექტები {#configuration-cache-and-isolated-projects}

პლაგინი მხარს უჭერს Gradle-ის კონფიგურაციის ქეშს და [იზოლირებულ პროექტებს](https://docs.gradle.org/current/userguide/isolated_projects.html). შეინარჩუნეთ პლაგინი `settings.gradle.kts`-ში; არ არის საჭირო მისი ცალ-ცალკე გამოყენება თითოეულ ქვეპროექტზე.

Tuist არ რთავს ამ ფუნქციებს ავტომატურად. მათ ჩასართავად, დაამატეთ შემდეგი `gradle.properties`-ში:

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

თქვენმა ბილდის სკრიპტებმა და სხვა პლაგინებმა ასევე უნდა მხარი დაუჭირონ ამ ფუნქციებს. Gradle აცნობებს თავსებადობის პრობლემებს კონფიგურაციის ქეშის შენახვისას.

## პრივიუების გამოქვეყნება {#publish-previews}

Android აპლიკაციის მოდულებისთვის, პლაგინი არეგისტრირებს `tuistShare<Variant>` ტასკებს:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

ტასკი აგებს და ამოწმებს ერთ ხელმოწერილ APK-ს, შემდეგ კი აქვეყნებს მას თქვენი არსებული Tuist ავტორიზაციით. ტასკის გამოძახება წარმოადგენს ჩართვის მექანიზმს: ჩვეულებრივი `assemble`, `build` და ტესტების ტასკები არ აქვეყნებენ პრივიუებს. CLI ატვირთვის ეტაპი არ არის საჭირო. იხილეთ <.localized_link href="/guides/features/previews/gradle">Gradle პრივიუები</.localized_link> უფლებამოსილების, ქეშის აღდგენისა და შეცდომების ქცევის შესახებ.

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `settings.gradle.kts`-ში მდებარე `tuist` გაფართოების ბლოკში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (არასავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. თუ არ არის მითითებული, პლაგინი კითხულობს მას `tuist.toml`-დან. |
| `url` | `String?` | `null` | Tuist სერვერის ბაზის URL. თუ არ არის მითითებული, ნაგულისხმევად იყენებს `"https://tuist.dev"`-ს ან `tuist.toml`-ში განსაზღვრულ მნიშვნელობას. |
| `uploadInBackground` | `Boolean?` | `null` | ატვირთოს თუ არა ბილდისა და ტესტების ანალიტიკა ფონურ რეჟიმში. როდესაც მნიშვნელობა არის `null` (ნაგულისხმევი), ატვირთვები ფონურ რეჟიმში ხდება ლოკალური ბილდებისთვის და წინა პლანზე უწყვეტი ინტეგრაციის გამშვებლებზე. |
| `stressNewTests.mode` | `String?` | `null` | `"report"` ან `"enforce"`. ხელახლა უშვებს ბილდის მიერ დამატებულ ტესტის შემთხვევებს და აღნიშნავს ნებისმიერს, რომელიც არასტაბილურია; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">ახალი ტესტების დატვირთული ტესტირება</.localized_link>. გამორთულია, თუ არ არის მითითებული. |
| `coverage.enabled` | `Boolean?` | `null` | ზომავს ტესტების დაფარვას JaCoCo-ს საშუალებით და ატვირთავს მას ყოველ ტესტების გაშვებაზე. გამორთულია, თუ არ არის მითითებული. `TUIST_TEST_COVERAGE` გარემოს ცვლადი გადაფარავს მას; იხილეთ <.localized_link href="/guides/features/test-code-coverage/gradle">Gradle კოდის დაფარვა</.localized_link>. |

ლოკალური სერვერისთვის, რომელიც იყენებს `http://` URL-ს, დაუშვით არაუსაფრთხო პროტოკოლი მხოლოდ ამ ლოკალურ კონფიგურაციაში:

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

არ ჩართოთ `allowInsecureProtocol` ჰოსტინგზე განთავსებული ან სხვა `https://` სერვერებისთვის.

> [!NOTE]
> **Tuist.toml**
>
> `project`-ის (და სურვილისამებრ `url`-ის) კონფიგურაციის რეკომენდებული გზა არის `tuist.toml` ფაილის გამოყენება თქვენი პროექტის ძირითად დირექტორიაში. ამ გზით კონფიგურაცია საერთოა Tuist ბრძანების სტრიქონის ინტერფეისსა და Gradle პლაგინს შორის. საჭიროების შემთხვევაში, შეგიძლიათ გადაფაროთ ეს მნიშვნელობები `settings.gradle.kts`-ში.

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP პროქსი {#http-proxy}

თუ თქვენი ქსელი გამავალ ტრაფიკს HTTP პროქსის მეშვეობით ატარებს, იხილეთ <.localized_link href="/guides/integrations/http-proxy">HTTP პროქსის სახელმძღვანელო</.localized_link>.

## შემდეგი ნაბიჯები {#next-steps}

პლაგინის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ ჩართოთ:

- <.localized_link href="/guides/features/cache/gradle-cache">დაშორებული ბილდის ქეში</.localized_link>, რათა გაუზიაროთ ბილდის არტეფაქტები თქვენს გუნდსა და უწყვეტი ინტეგრაციის გამშვებებს.
- <.localized_link href="/guides/features/build-insights/gradle">ბილდის ანალიტიკა</.localized_link>, რათა დააკვირდეთ ამოცანების შესრულების დროსა და ქეშის ქცევას Tuist-ის დაფაზე.
- <.localized_link href="/guides/features/test-insights/gradle">ტესტების ანალიტიკა</.localized_link>, რათა დააკვირდეთ ტესტების შესრულებას და აღმოაჩინოთ არასტაბილური ტესტები.
- <.localized_link href="/guides/features/test-insights/flaky-tests">არასტაბილური ტესტები</.localized_link>, რათა ავტომატურად აღმოაჩინოთ, თვალყური ადევნოთ და იზოლირება მოახდინოთ არასტაბილური ტესტების.
- <.localized_link href="/guides/features/test-code-coverage/gradle">კოდის დაფარვა</.localized_link>, რათა მიჰყვეთ თქვენი ტესტების დაფარვას კომიტის, პროექტისა და ფაილის მიხედვით.
