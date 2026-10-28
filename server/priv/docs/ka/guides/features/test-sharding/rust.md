---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Rust-ის ტესტების დაყოფა {#rust-test-sharding}

Tuist არ ყოფს ჩვეულებრივ `cargo test` გაშვებებს და არ ანაწილებს მათ კომპილირებულ ტესტებს CI სამუშაოებზე. shard-plan გარემოს ცვლადების დაყენება არ ცვლის იმას, თუ რომელ ტესტებს ასრულებს Cargo.

გაუშვით თქვენი ტესტები ერთიანი CI სამუშაოს ფარგლებში:

```sh
tuist cargo test --workspace
```

Cargo მართავს ლოკალურ ტესტების პარალელიზმს, ხოლო Tuist აწვდის შედეგებს, doctests-ის ჩათვლით. დეტალებისთვის იხილეთ <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

შეგიძლიათ გამოიყენოთ Cargo-ს პაკეტების შერჩევა და ტესტების ფილტრები, რათა განსაზღვროთ, თუ რას შეასრულებს თითოეული სამუშაო, მაგრამ ეს სამუშაოები დამოუკიდებელი გაშვებებია და არა Tuist-ის მიერ მართული ნაწილები.
