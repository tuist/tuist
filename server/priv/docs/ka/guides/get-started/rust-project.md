---
{
  "title": "Rust პროექტი",
  "titleTemplate": ":title · დაწყება · სახელმძღვანელოები · Tuist",
  "description": "დააკავშირეთ თქვენი Rust პროექტი Tuist-თან, რათა თვალი ადევნოთ ბილდებსა და ტესტებს, მათ შორის doctests-ს, და აღმოაჩინოთ არასტაბილური ტესტები."
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

- Rust-ის პროექტი, აგებული Cargo-ით.
- Tuist CLI და Tuist-ის ანგარიში.

Tuist მუშაობს თქვენს არსებულ Cargo-ს პროექტთან. არ არის საჭირო Rust-ის დამოკიდებულების დამატება ან პროექტის აგების პროცესის შეცვლა.

## პროექტის მიერთება

დააინსტალირეთ <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> და Rust. შექმენით პროექტი დაფარდზე ისე, რომ აგების სისტემად მითითებული იყოს **Cargo (Rust)**. შემდეგ დაამატეთ პროექტი სამუშაო სივრცის ძირეულ `Cargo.toml`-ში:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo უგულებელყოფს `metadata` ცხრილებს, ამიტომ ეს არ ცვლის თქვენი პროექტის აგების პროცესს. ერთი კრეიტისთვის, რომელსაც არ აქვს `[workspace]` ცხრილი, გამოიყენეთ `[package.metadata.tuist]`. ცხრილი იღებს იმავე პარამეტრებს, რასაც `tuist.toml` ფაილი, რომლის გამოყენებაც შეგიძლიათ ამის ნაცვლად, მაგალითად, როდესაც რეპოზიტორიაში ასევე არის სხვა აგების სისტემების პროექტები. როდესაც ორივე არსებობს, უპირატესობა ენიჭება `tuist.toml`-ს.

შედით სისტემაში `tuist auth login`-ით, შემდეგ გაუშვით თქვენი ჩვეულებრივი Cargo-ს ბრძანებები Tuist-ის მეშვეობით. CI-ში, ავთენტიკაცია მოახდინეთ თქვენი CI პროვაიდერის OIDC იდენტობით ან დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>. ასევე შეგიძლიათ დააყენოთ `TUIST_PROJECT` კონფიგურაციის ფაილის დამატების ნაცვლად და `TUIST_URL`, თუ იყენებთ თვითმასპინძელ სერვერს.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

გამოიყენეთ იგივე არგუმენტები, რომლებსაც ჩვეულებრივ გადასცემთ Cargo-ს, მათ შორის ფუნქციები, ხელსაწყოების ჯაჭვები და ტესტების ფილტრები. Cargo ინარჩუნებს ჩვეულებრივ გამოსავალს და გასვლის კოდს, მაშინაც კი, თუ Tuist ვერ ატვირთავს ანგარიშს.

## განაგრძეთ Cargo-ს ბრძანებების შეყვანა

[mise-ის ბრძანებების გარსების](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) ჩართვისას, დაამატეთ ეს `mise.toml`-ში:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

გაუშვით `mise reshim` გარსის დამატების შემდეგ. შემდეგ შეგიძლიათ გამოიყენოთ `cargo build`, `cargo check` და `cargo test` ჩვეულებრივად. Mise მათ Tuist-ის მეშვეობით გაუშვებს.

> [!TIP] Coding agents
> ეს სასარგებლოა კოდის აგენტებთან მუშაობისას: მათ შეუძლიათ განაგრძონ `cargo build` და `cargo test` გაშვება `tuist` პრეფიქსის დამატების შეხსენების გარეშე.

## კომპილაციის ქეში

`tuist cargo build` ავტომატურად ათავსებს ქეშში შესაბამის კომპილაციებს, დამოკიდებულებებს და აგების სკრიპტების გაშვებებს, ლოკალურად და Kura-ს დისტანციური ქეშის მეშვეობით. დამატებითი ხელსაწყოს ან ქეშის კონფიგურაცია არ არის საჭირო. ქეში ექსპერიმენტულია, დადასტურებულია Apple silicon Mac-ებზე და ჯერ არ მოიცავს ყველა კომპილაციას. მხარდაჭერილი კომპილაციების, ავთენტიკაციის და ხელახლა გამოყენების შემოწმების შესახებ იხილეთ <.localized_link href="/guides/features/cache/rust">Rust-ის ქეში</.localized_link>.

## აგების ანალიტიკა

გახსენით **აგებები** დაფარდზე, რათა ნახოთ, რამდენ ხანს გრძელდება თქვენი აგებები და შეადაროთ ლოკალური აგებები CI-სთან. აირჩიეთ აგება, რათა იპოვოთ კრეიტები, რომელთა კომპილაციასაც ყველაზე მეტი დრო დასჭირდა და შეამოწმოთ მათი გაფრთხილებები და შეცდომები.

კომპილატორის დროის მონაცემები ეხება კრეიტებს, არა ცალკეულ საწყის ფაილებს. აგების ანგარიშის წაკითხვის შესახებ მეტის გასაგებად იხილეთ <.localized_link href="/guides/features/build-insights/rust">Rust-ის აგების ანალიტიკა</.localized_link>.

## ტესტების ანალიტიკა

გაუშვით თქვენი ტესტები ჩვეულებრივად:

```sh
tuist cargo test --workspace
```

გახსენით **ტესტები** დაფარდზე, რათა ნახოთ წარმატებული, წარუმატებელი და იგნორირებული ტესტები, doctests-ის ჩათვლით. Cargo ანგარიშდება სუიტების ხანგრძლივობას, მაგრამ სტაბილური libtest არ ასახავს თითოეული ტესტის დროს.

მხოლოდ doctests-ის გასაშვებად:

```sh
tuist cargo test --doc
```

მეტის წასაკითხად იხილეთ <.localized_link href="/guides/features/test-insights/rust">Rust-ის ტესტების ანალიტიკა</.localized_link> და <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Rust-ის არასტაბილური ტესტები</.localized_link>.

## სავაჭრო ნიშნები {#trademarks}

Rust და Cargo არის Rust Foundation-ის სავაჭრო ნიშნები. Tuist არ არის დაკავშირებული ან დადასტურებული Rust Project-ის ან Rust Foundation-ის მიერ. Rust-ის ლოგო ამ სახელმძღვანელოებში არის © Rust Foundation, გამოყენებულია [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ლიცენზიის შესაბამისად და ნაჩვენებია ერთ ფერში, რომელიც შეესაბამება გვერდის თემას.
