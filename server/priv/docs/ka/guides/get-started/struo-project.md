---
{
  "title": "Struo პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დააკავშირეთ Struo Tuist-თან გაზიარებული ქეშირების, ბილდისა და ტესტების ცოცხალი ანალიტიკის, ტესტების შარდირებისა და აპლიკაციის პრივიუებისთვის."
}
---
# Struo-ს პროექტი {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) ასრულებს ქეშირებად სკრიპტებსა და აგების გრაფებს. დააკავშირეთ ის Tuist-თან, რათა გაინაწილოთ ქეშირებული სამუშაო მანქანებს შორის, თვალყური ადევნოთ შესრულებას რეალურ დროში და გამოაქვეყნოთ აპლიკაციები თქვენი გუნდისთვის ტესტირების მიზნით. შეინარჩუნეთ არსებული პროექტის წყაროები და აგების განმარტებები; ინტეგრაცია მოთავსებულია `struo.toml` ფაილში.

## წინაპირობები

- დაყენებული უნდა იყოს [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) ან უფრო ახალი ვერსია, ასევე საჭიროა სამუშაო სივრცე ან ქეშირებადი სკრიპტი. მიჰყევით [დაყენების სახელმძღვანელოს](https://struo.run/docs/guide/getting-started), ან დააფიქსირეთ ვერსია mise-ის საშუალებით:

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Tuist-ის ანგარიში. Struo-ს ინტეგრაციისთვის Tuist CLI არ არის საჭირო.

## Once-დან Struo-ზე გადასვლა {#upgrading-from-once}

Struo არის Once-ის ახალი სახელი. გადაარქვით `once.toml` ფაილებს სახელი `struo.toml`, განაახლეთ mise-ის ფიქსაციები `github:tuist/once`-დან `github:tuist/struo`-ზე და ჩაანაცვლეთ `once` ბრძანებები `struo`-ით. განაახლეთ სკრიპტების სათაურები `# once`-დან `# struo`-ზე და shebang ხაზები `#!/usr/bin/env -S struo exec -- bash`-ზე. გადაარქვით `ONCE_*` გარემოს ცვლადებს სახელი `STRUO_*`-ად, მაგალითად `STRUO_CACHE_PROVIDER`; Tuist-ის ავტორიზაციის მონაცემები კვლავ იყენებენ `TUIST_TOKEN`-ს.

შეცვალეთ `.once/` ჩანაწერები ignore ფაილებში `.struo/`-ზე. გამოტანილი ფაილები ახლა ინახება `.struo/out/` საქაღალდეში, ხოლო გაზიარებული ლოკალური შინაარსის ქეში იყენებს `$XDG_CACHE_HOME/struo/cas`-ს (ნაგულისხმევად `~/.cache/struo/cas`). ქეშის გასაღებები და ლოკალური საცავი იყენებენ ახალ სახელს, ამიტომ განახლების შემდეგ ელოდეთ ცივ ლოკალურ ქეშს ძველი ქეშის ჩანაწერების გადატანის ნაცვლად. ხელახლა შედით სისტემაში ბრძანებით `struo auth login --provider tuist`.

სახელის შეცვლა არ ცვლის Tuist-ის თავსებადობის წერტილებს: რეალურ დროში ანგარიშგება კვლავ იყენებს `once.events.v1`-ს, ხოლო არსებული `/api/.../once` მარშრუტები კვლავ მხარდაჭერილია. იხილეთ [upstream rename guide](https://struo.run/changelog/2026-11-18-once-is-now-struo).

## პროექტის დაკავშირება {#connect-the-project}

თქვენი რეპოზიტორიის ფესვიდან გაუშვით:

```bash
struo connect --provider tuist --create
```

Struo საჭიროების შემთხვევაში გაგივლით ავტორიზაციას, შექმნის Tuist-ის პროექტს თქვენს პირად ანგარიშზე და ჩაწერს პროვაიდერთან დაკავშირების მონაცემებს `struo.toml` ფაილში. იხილეთ [Connect a project](https://struo.run/docs/guide/infrastructure/connect) სხვა ანგარიშის ან არსებული პროექტის არჩევისთვის.

არსებული Tuist-ის პროექტისთვის, პროვაიდერი და ქეშთან დაკავშირება თავად დააკონფიგურირეთ:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

ჩაანაცვლეთ `acme` და `app` თქვენი ანგარიშისა და პროექტის იდენტიფიკატორებით, შემდეგ გაიარეთ ავტორიზაცია:

```bash
struo auth login --provider tuist
```

დააკომიტეთ `struo.toml`, რათა თქვენმა გუნდის წევრებმა და CI-მ გაიზიარონ დანიშნულება, არა თქვენი ავტორიზაციის მონაცემები. თითოეული დეველოპერი შედის სისტემაში საკუთარ მანქანაზე.

## გაზიარებული ქეში

ლოკალური ქეში მხოლოდ იმ მანქანას ეხმარება, რომელმაც ის შექმნა. Tuist-ის კონფიგურაციით, Struo-ს შეუძლია აღადგინოს სხვა დეველოპერის ან CI-ის მიერ შექმნილი შესაბამისი შედეგები იმავე სამუშაოს ხელახლა შესრულების ნაცვლად.

ჩვეულებრივად გაუშვით თქვენი ქეშირებადი სკრიპტი ან გრაფის სამიზნე:

```bash
struo build MyApplication
```

გახსენით **Struo Cache** დაფაზე, რათა შეამოწმოთ დისტანციური ქეშის აქტივობა. იხილეთ <.localized_link href="/guides/features/cache/struo">Struo cache</.localized_link> დაყენებისა და მანქანებს შორის ხელახალი გამოყენების შემოწმებისთვის.

## აგების ანალიტიკა

Struo ასრულების დაწყებისას ბეჭდავს დაფის ბმულს. გახსენით ის, რათა თვალყური ადევნოთ გრაფს, მოქმედებების სტატუსსა და ქეშის გადაწყვეტილებებს შესრულების პროცესში. გამოიყენეთ **Builds** ლოკალური და CI შესრულების შესადარებლად და წარუმატებელი მოქმედებების გამოსაკვლევად. შეინარჩუნეთ CI ლოგები პროცესის სრული გამოტანისთვის; მოქმედებების ნედლი ლოგების მიღება ამჟამად არ არის ხელმისაწვდომი.

იხილეთ <.localized_link href="/guides/features/build-insights/struo">Struo build insights</.localized_link>, რათა გაიგოთ, რა ინახება და როგორ მივუდგეთ მას კოდირების აგენტებიდან ან Grafana-დან.

## ტესტების ანალიტიკა და შარდინგი

გაუშვით თქვენი Struo-ს ტესტების სამიზნეები:

```bash
struo test
```

გახსენით **Tests**, რათა შეამოწმოთ მოხსენებული სიუიტები, ტესტ-ქეისები, ხანგრძლივობა და შეცდომები. შედეგები დამოკიდებულია ტესტის სამიზნის მოხსენების შესაძლებლობებზე; მოქმედება, რომელიც ასრულებს ტესტის პროცესს, არ არის ავტომატურად ტესტ-ქეისების დონის მოხსენება.

როდესაც სიუიტი ერთ მანქანას აღემატება, შექმენით ჰოსტინგული შარდინგის გეგმა და გაანაწილეთ მისი პაკეტები CI worker-ებზე. იხილეთ <.localized_link href="/guides/features/test-insights/struo">Struo test insights</.localized_link> და <.localized_link href="/guides/features/test-sharding/struo">Struo test sharding</.localized_link>.

## პრივიუები და ბანდლის ზომა

დაამატეთ არტიფაქტის დაკავშირება იმავე პროვაიდერთან, რათა გამოაქვეყნოთ მხარდაჭერილი Android, Apple სიმულატორისა და macOS აპლიკაციები:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

მიღებული ბმული ხსნის თქვენი პროექტის პრივიუებს; დამუშავებას შეიძლება რამდენიმე წუთი დასჭირდეს. იხილეთ <.localized_link href="/guides/features/previews/struo">Struo previews</.localized_link> ხელმოწერის მოთხოვნებისა და აგების შემდეგ არჩევითი გამოქვეყნებისთვის.

ბანდლის ზომის თვალყურის დევნებისთვის, ცალკე გამოიყენეთ Tuist CLI აგებულ `.app`, `.ipa`, `.xcarchive`, `.apk`, ან `.aab` ფაილზე. მიჰყევით <.localized_link href="/guides/features/bundle-insights">Apple ან Android ბანდლის ანალიტიკის სახელმძღვანელოს</.localized_link>; Struo-ს არტიფაქტის გამოქვეყნება ავტომატურად არ ტვირთავს ბანდლის ზომის მოხსენებას.

## უწყვეტი ინტეგრაცია

გამოიყენეთ ანგარიშის ტოკენი, რომელიც ავტორიზებულია პროექტის ოპერაციებისთვის `TUIST_TOKEN`-ში, ან გაიარეთ ავტორიზაცია მხარდაჭერილი CI პროვაიდერის OpenID Connect იდენტობის მეშვეობით:

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

GitHub Actions-ზე, მიანიჭეთ ჯობს `id-token: write` და `contents: read`. იხილეთ <.localized_link href="/guides/integrations/continuous-integration#struo">Struo on continuous integration</.localized_link> მაგალითისთვის. პირადი დეველოპერის შესვლა არ არის CI-ის ავტორიზაციის მონაცემი.

## დისტანციური შესრულება

ანგარიშები, რომლებზეც ჩართულია დისტანციური შესრულება, ასევე შეუძლიათ შეასრულონ შესაბამისი გრაფის ბრძანებების მოქმედებები Tuist-ის Linux worker-ებზე. ეს განცალკევებულია ქეშირებული შედეგების გაზიარებისა და მთლიანი CI workflow-ის შესრულებისგან. იხილეთ <.localized_link href="/guides/features/runners/struo">Struo remote execution</.localized_link> worker-ების მოთხოვნებისა და დაყენებისთვის.
