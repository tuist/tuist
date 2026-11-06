---
{
  "title": "Rust-ის პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დაუკავშირეთ თქვენი Rust-ის პროექტი Tuist-ს ბილდებისა და ტესტების, მათ შორის doctests-ის, თვალყურის დევნებისა და არასტაბილური ტესტების აღმოჩენის მიზნით."
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

- Cargo-თი აგებული Rust-ის პროექტი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-ს პროექტთან. არ გჭირდებათ Rust-ის დამოკიდებულების დამატება ან თქვენი პროექტის აგების წესის შეცვლა.

## პროექტის მიერთება

დააყენეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაფარდაზე, სადაც აგების სისტემად მითითებულია **Cargo (Rust)**. დაამატეთ `tuist.toml` თქვენი რეპოზიტორიის ფესვში:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით ჩვეულებრივი Cargo-ს ბრძანებები Tuist-ის მეშვეობით. CI-ში მიანიჭეთ `TUIST_TOKEN`-ს პროექტის ტოკენი. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რომლებსაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის features, toolchains და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამოტანას და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## განაგრძეთ Cargo-ს ბრძანებების შეყვანა

[mise-ის ბრძანებების გამხვევების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გამხვევის დამატების შემდეგ გაუშვით `mise reshim`. შემდეგ შეგიძლიათ ჩვეულებრივად გამოიყენოთ `cargo build`, `cargo check` და `cargo test`. Mise მათ თქვენთვის Tuist-ის მეშვეობით ასრულებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდის აგენტებთან მუშაობისას: მათ შეუძლიათ განაგრძონ `cargo build` და `cargo test` გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად აქეშებს შესაბამის რეესტრის ფოთლის ბიბლიოთეკებს, ლოკალურად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ხელსაწყოს ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია და ჯერ არ მოიცავს ყველა კომპილაციას ან ხელახლა გამოყენებას სხვადასხვა checkout ბილიკებზე. იხილეთ <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link> მხარდაჭერილი კომპილაციების, ავთენტიკაციის და ხელახლა გამოყენების შემოწმების შესახებ.

## აგების ანალიტიკა

გახსენით **Builds** დაფარდაზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ლოკალური აგებები CI-ს. აირჩიეთ აგება, რათა იპოვოთ ყველაზე დიდხანს კომპილირებადი crates და შეამოწმოთ მისი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება crates-ს, არა ცალკეულ საწყის ფაილებს. იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link> აგების ანგარიშის წაკითხვის შესახებ დამატებითი ინფორმაციისთვის.

## ტესტების ანალიტიკა

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **Tests** დაფარდაზე, რათა ნახოთ წარმატებული, ჩავარდნილი და უგულებელყოფილი ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშდება suite-ების ხანგრძლივობას, მაგრამ stable libtest არ ავლენს თითოეული ტესტის დროის მონაცემებს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

წაიკითხეთ მეტი <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>-ში.
