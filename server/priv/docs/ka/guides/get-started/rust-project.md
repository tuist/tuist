---
{
  "title": "Rust project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect your Rust project to Tuist to track builds and tests, including doctests, and find flaky tests."
}
---
# Rust-ის პროექტი {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## წინაპირობები

- Cargo-ით აგებული Rust-ის პროექტი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-ს პროექტთან. არ გჭირდებათ Rust-ის დამოკიდებულების დამატება ან თქვენი პროექტის აგების პროცესის შეცვლა.

## პროექტის მიერთება

დააყენეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაფარდზე, სადაც აგების სისტემად მითითებული იქნება **Cargo (Rust)**. დაამატეთ `tuist.toml` თქვენი რეპოზიტორიის ძირში:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით თქვენი ჩვეულებრივი Cargo ბრძანებები Tuist-ის მეშვეობით. CI-ში, მიანიჭეთ `TUIST_TOKEN` პროექტის ტოკენი. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად, და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რომლებსაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის features, toolchains და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამომავალ მონაცემებს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## აგრძელეთ Cargo-ს ბრძანებების შეყვანა

[mise-ის ბრძანებების შემფუთავების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გაუშვით `mise reshim` შემფუთავის დამატების შემდეგ. ამის შემდეგ შეგიძლიათ გამოიყენოთ `cargo build`, `cargo check`, და `cargo test` როგორც ჩვეულებრივ. Mise მათ Tuist-ის მეშვეობით გაუშვებს თქვენთვის.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდირების აგენტებთან მუშაობისას: მათ შეუძლიათ აგრძელონ `cargo build` და `cargo test` გაშვება `tuist` პრეფიქსის დამატების გახსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად აქეშებს შესაბამის რეესტრის leaf ბიბლიოთეკებს, ლოკალურად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ხელსაწყოს ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია და ჯერ არ მოიცავს ყველა კომპილაციას ან ხელახლა გამოყენებას სხვადასხვა checkout ბილიკებში. იხილეთ <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link> მხარდაჭერილი კომპილაციების, ავთენტიკაციის და ხელახლა გამოყენების შემოწმების შესახებ.

## აგების ანალიტიკა

გახსენით **Builds** დაფარდზე, რათა ნახოთ, თუ რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ლოკალური აგებები CI-სთან. აირჩიეთ აგება, რათა იპოვოთ კრეიტები, რომელთა კომპილაციასაც ყველაზე მეტი დრო დასჭირდა და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება კრეიტებს, არა ცალკეულ საწყის ფაილებს. იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link> აგების ანგარიშის წაკითხვის შესახებ მეტი ინფორმაციისთვის.

## ტესტების ანალიტიკა

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **Tests** დაფარდზე, რათა ნახოთ წარმატებული, წარუმატებელი და გამოტოვებული ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშობს ტესტების ნაკრების ხანგრძლივობას, მაგრამ სტაბილური libtest არ აჩვენებს ცალკეული ტესტების დროს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

იხილეთ მეტი <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>-ში.
