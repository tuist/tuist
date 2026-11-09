---
{
  "title": "Rust-ის პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დააკავშირეთ თქვენი Rust-ის პროექტი Tuist-თან, რათა აკონტროლოთ კომპილაციები და ტესტები, მათ შორის doctests, და აღმოაჩინოთ არასტაბილური ტესტები."
}
---
# Rust-პროექტი {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## წინაპირობები

- Cargo-ით აგებული Rust-პროექტი.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-პროექტთან. არ არის საჭირო Rust-დამოკიდებულების დამატება ან პროექტის აგების წესის შეცვლა.

## პროექტის მიერთება

დააინსტალირეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაშბორდზე, სადაც აგების სისტემად მითითებულია **Cargo (Rust)**. დაამატეთ `tuist.toml` თქვენი რეპოზიტორიის ფესვში:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით ჩვეულებრივი Cargo-ბრძანებები Tuist-ის მეშვეობით. CI-ში გაიარეთ ავთენტიფიკაცია თქვენი CI-პროვაიდერის OIDC-იდენტობით ან დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად და `TUIST_URL`, თუ იყენებთ საკუთარ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რომლებსაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის features, toolchains და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამომავალ მონაცემებს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## აგრძელეთ Cargo-ს ბრძანებების შეყვანა

[mise-ის ბრძანების გარსების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გარსის დამატების შემდეგ გაუშვით `mise reshim`. ამის შემდეგ ჩვეულებრივად გამოიყენეთ `cargo build`, `cargo check` და `cargo test`. Mise მათ თქვენთვის Tuist-ის მეშვეობით ასრულებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდის აგენტებთან მუშაობისას: მათ შეუძლიათ აგრძელონ `cargo build` და `cargo test`-ის გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად აქეშებს შესაბამის კომპილაციებს, დამოკიდებულებებს და build-script-ების გაშვებებს, ლოკალურად და Kura-ს შორეული ქეშის მეშვეობით. დამატებითი ხელსაწყოს ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია, დადასტურებულია Apple silicon Mac-ებზე და ჯერ არ ფარავს ყველა კომპილაციას. მხარდაჭერილი კომპილაციების, ავთენტიფიკაციის და ხელახლა გამოყენების შემოწმების შესახებ იხილეთ <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link>.

## აგების ანალიტიკა

გახსენით **Builds** დაშბორდზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ლოკალური აგებები CI-ს. აირჩიეთ აგება, რათა იპოვოთ კრეიტები, რომელთა კომპილაციას ყველაზე მეტი დრო დასჭირდა, და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება კრეიტებს, არა ცალკეულ საწყის ფაილებს. აგების ანგარიშის წაკითხვის შესახებ მეტის გასაგებად იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust Build Insights</.localized_link>.

## ტესტების ანალიტიკა

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **Tests** დაშბორდზე, რათა ნახოთ წარმატებული, წარუმატებელი და უგულებელყოფილი ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშდება სუიტების ხანგრძლივობას, მაგრამ სტაბილური libtest არ ასახელებს თითოეული ტესტის დროს.

მხოლოდ doctests-ების გასაშვებად:

```sh
tuist cargo test --doc
```

მეტის წასაკითხად იხილეთ <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust Flaky Tests</.localized_link>.
