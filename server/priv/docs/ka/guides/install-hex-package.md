---
{
  "title": "Hex პაკეტის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და მოახდინოთ Tuist-ის Hex პაკეტის კონფიგურაცია თქვენს Elixir პროექტში."
}
---
# Hex პაკეტის ინსტალაცია {#install-the-hex-package}

Tuist გთავაზობთ [Hex](https://hex.pm/packages/tuist_ex) პაკეტს, `tuist_ex`, რომელიც ინტეგრირდება თქვენს Elixir პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/build-insights/elixir">ბილდის ანალიტიკა</.localized_link> და <.localized_link href="/guides/features/test-insights/elixir">ტესტების ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ მის ინსტალაციასა და კონფიგურაციაში.

პაკეტი მოითხოვს Elixir 1.18-ს ან უფრო გვიან ვერსიას. მას არ სჭირდება Tuist-ის ბრძანებათა ხაზის ინტერფეისი.

## 1. შექმენით პროექტი {#create-the-project}

შექმენით პროექტი Tuist-ის დაფაზე და აირჩიეთ **Mix (Elixir)** როგორც მისი ბილდის სისტემა. მისი იდენტიფიკატორი, `account/project`, აკავშირებს თქვენს Mix პროექტს მასთან.

## 2. დაამატეთ პაკეტი {#add-the-package}

დაამატეთ `tuist_ex` დამოკიდებულებებში თქვენს `mix.exs`-ში:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

შემდეგ მიიღეთ ის:

```bash
mix deps.get
```

`runtime: false` ტოვებს Tuist-ს თქვენი გაშვებული აპლიკაციის გარეთ. გააგრძელეთ <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir-ის დაწყებით</.localized_link> ერთდროულად ქეშირების, ბილდის ანალიტიკისა და ტესტების ანალიტიკის კონფიგურაციისთვის. ქვემოთ მოცემული სექციები მოიცავს ავთენტიკაციასა და კონფიგურაციის დეტალებს.

## 3. ავთენტიკაცია თქვენი გუნდისა და უწყვეტი ინტეგრაციისთვის {#authenticate}

თითოეული გუნდის წევრი ასრულებს შემდეგს, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
mix tuist.login
```

ის ხსნის ბრაუზერს და ელოდება თქვენს ავტორიზაციას. ბრაუზერის გარეშე შესასვლელად, გადაეცით თქვენი სარწმუნოებები:

```bash
mix tuist.login --email person@example.com --password secret
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, დააყენეთ მისი საბაზისო URL `mix.exs`-ში, ან გადაეცით ის `--url`-ით:

```bash
mix tuist.login --url http://localhost:8080
```

შეინახეთ ჰოსტის სახელის მართლწერა თანმიმდევრული. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

GitHub Actions-ზე, CircleCI-ზე და Bitrise-ზე, უწყვეტ ინტეგრაციას არ სჭირდება შესვლის ნაბიჯი. პირველად, როდესაც ამოცანა აგზავნის ანგარიშს, ის ცვლის პროვაიდერის OpenID Connect ტოკენს Tuist-ის ტოკენზე. <.localized_link href="/guides/integrations/gitforge/github">დააკავშირეთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან და GitHub Actions-ზე მიანიჭეთ სამუშაოს `id-token: write` ნებართვა:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

ნებისმიერი სხვა OpenID Connect იდენტობის პროვაიდერთან, როგორიცაა Fly.io Machines, დააკონფიგურირეთ workload identity trust policy თქვენი ანგარიშის **Workload identities** სექციაში **Settings → Authentication** გვერდზე, რაც CI-ს ანიჭებს წვდომას ამ ანგარიშის ყველა მიმდინარე და მომავალ პროექტზე. დააყენეთ `TUIST_OIDC_ACCOUNT` იმ Tuist ანგარიშზე, რომელიც ფლობს პროექტს, და მიეწოდეთ ახლად შექმნილი იდენტობის ტოკენი პოლიტიკის audience-ით `TUIST_OIDC_TOKEN`-ის მეშვეობით. ინტეგრაცია ავტომატურად ცვლის მას, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან ვალიდური შენახული შესვლა; `mix tuist.login` ასევე იღებს მას CI-ს გარეთ. ავტომატური ცვლა ხელახლა იყენებს ვადაუწურავ სესიას მხოლოდ იმავე სერვერის, ანგარიშისა და მიწოდებული იდენტობის ტოკენისთვის. ამ იდენტობის შეცვლა იწვევს ახალ ცვლას, ხოლო ცარიელი მიწოდებული იდენტობა ვერ ახდენს ადრეული სესიის ხელახლა გამოყენებას. Tuist-ის სესიები გრძელდება ერთი საათის განმავლობაში refresh token-ების გარეშე, ამიტომ უფრო ხანგრძლივი სამუშაოებისთვის, შექმენით ახალი იდენტობის ტოკენი და გაუშვით `mix tuist.login` ხელახლა სესიის ვადის გასვლამდე. მიჰყევით <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">workload identity-ის კონფიგურაციას</.localized_link> და <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io-ს მაგალითს</.localized_link>.

fork-ებიდან შემოსულ pull request-ებს არ ენიჭებათ OpenID Connect ტოკენი, ამიტომ მათი გაშვებები არ იგზავნება და ჩვეულებრივად გადიან ან ვერ გადიან. სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` გარემოს ცვლადი ანგარიშის ტოკენზე. მიჰყევით <.localized_link href="/guides/integrations/continuous-integration#authentication">უწყვეტი ინტეგრაციის ავთენტიკაციის სახელმძღვანელოს</.localized_link> ერთის შესაქმნელად.

## 4. გააგრძელეთ `mix test`-ისა და `mix compile`-ის გამოყენება {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">გაზიარებული კონფიგურაცია</.localized_link> აინსტალირებს კომპილაციისა და ტესტების ალიასებს თქვენთვის. `mix test test/my_app_test.exs:12 --trace` აგზავნის გაშვების ანგარიშს იმავე გამომავალი მონაცემებითა და გასვლის კოდით, ხოლო კომპილაციის ინტეგრაცია მოიცავს ბილდებს, რომლებიც გამოწვეულია `mix test`-ით ან `mix phx.server`-ით. კომპილაცია, რომელიც არ პოულობს საკეთებელს, არ იგზავნება.

ამოცანები ასევე მუშაობენ, როდესაც მათ უწოდებთ მათი საკუთარი სახელით. Mix იწყებს ასე დაწერილ ამოცანას `dev` გარემოში, ამიტომ ამოცანა უნდა დაიწყოს თავიდან მეორე პროცესში ტესტის გარემოსთვის. დაამატეთ ამოცანები სასურველ გარემოებში ამის გამოსარიცხად:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist`-ის ქვეშ `mix.exs`-ის პროექტის პარამეტრებში:

| პარამეტრი | ტიპი | ნაგულისხმები | აღწერა |
| --- | --- | --- | --- |
| `project` | `String` | არ არის (სავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `url` | `String` | `"https://tuist.dev"` | Tuist სერვერის საბაზისო URL. |
| `cache` | `boolean` ან საკვანძო სიტყვების სია | გამორთული | კონფიგურაცია ააქტიურებს დამოკიდებულებების ქეშირებას. იხილეთ <.localized_link href="/guides/features/cache/elixir">Elixir ქეში</.localized_link> გამონაკლისებისა და დამატებითი შეყვანებისთვის. |
| `test_retries` | `integer` | `0` | რამდენჯერ უნდა განმეორდეს ვერ გასული ტესტები; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">ტესტების განმეორება</.localized_link>. |
| `tags` | `String`-ის სია | `[]` | ტეგები, რომლებიც მიემაგრება ყოველ ბილდს; იხილეთ <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">მორგებული მეტამონაცემები</.localized_link>. |
| `values` | რუკა | `%{}` | საკვანძო-მნიშვნელობის მონაცემები, რომლებიც მიემაგრება ყოველ ბილდს. |

გარემოს ცვლადებს აქვთ უპირატესობა `mix.exs`-თან შედარებით:

| ცვლადი | აღწერა |
| --- | --- |
| `TUIST_PROJECT` | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `TUIST_URL` | Tuist სერვერის საბაზისო URL. |
| `TUIST_TOKEN` | აუთენტიფიკაციის ტოკენი, შენახული შესვლის ნაცვლად. |
| `TUIST_OIDC_TOKEN` | ახლად გენერირებული OpenID Connect იდენტობის ტოკენი, რომელიც იცვლება Tuist ტოკენზე. მისი აუდიენსია უნდა იყოს `tuist` GitHub Actions-ისა და Bitrise-ისთვის, ან ემთხვეოდეს პროექტის ნდობის პოლიტიკას სხვა პროვაიდერებისთვის. გამოიყენება `mix tuist.login`-ით ან როგორც სათადარიგო ვარიანტი, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან მოქმედი შენახული შესვლა. |
| `TUIST_OIDC_ACCOUNT` | Tuist ანგარიშის სახელი, რომელიც ფლობს პროექტს. საჭიროა ჟეტონის გაცვლისას პროექტის ნდობის პოლიტიკის მეშვეობით. ის ირჩევს არსებულ ნდობის პოლიტიკებს და თავისთავად არ ანიჭებს წვდომას. |
| `TUIST_TEST_RETRIES` | რამდენჯერ უნდა განმეორდეს ვერ გასული ტესტები. |
| `TUIST_TAGS` | მძიმით გამოყოფილი ტეგები, რომლებიც მიემაგრება ბილდს. |
| `TUIST_VALUES` | მძიმით გამოყოფილი `key=value` წყვილები, რომლებიც მიემაგრება ბილდს. |
| `TUIST_DEBUG` | დააყენეთ `1`-ზე, რათა დაბეჭდოს, რატომ ვერ მოხერხდა ანგარიშის გაგზავნა. |

ანგარიშგება არასდროს ცვლის `mix test`-ის ან `mix compile`-ის გასვლის კოდს. თუ ანგარიშის გაგზავნა შეუძლებელია, ამოცანა არაფერს ამბობს, თუ არ არის დაყენებული `TUIST_DEBUG=1`.

## შემდეგი ნაბიჯები {#next-steps}

პაკეტის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ გამოიყენოთ:

- <.localized_link href="/guides/features/cache/elixir">დამოკიდებულებების ქეშირება</.localized_link> კომპილირებული დამოკიდებულებების ხელახლა გამოსაყენებლად ლოკალურად და CI ბილდებში.
- <.localized_link href="/guides/features/build-insights/elixir">ბილდის ანალიტიკა</.localized_link> კომპილაციის დროის, გაფრთხილებებისა და ბილდების შემაფერხებელი ფაქტორების თვალყურის სადევნებლად.
- <.localized_link href="/guides/features/test-insights/elixir">ტესტების ანალიტიკა</.localized_link> ტესტების შესრულების თვალყურის სადევნებლად თითოეულ ტესტამდე.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">არასტაბილური ტესტები</.localized_link> პერიოდულად მავალი ტესტების აღმოჩენისა და თვალყურის დევნებისთვის.
- <.localized_link href="/guides/features/test-sharding/elixir">ტესტების დაყოფა</.localized_link> თქვენი ტესტების გასანაწილებლად უწყვეტი ინტეგრაციის გამშვებებზე.
