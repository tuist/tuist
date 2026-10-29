---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Hex-პაკეტის ინსტალაცია {#install-the-hex-package}

Tuist გთავაზობთ [Hex](https://hex.pm/packages/tuist_ex)-პაკეტს, `tuist_ex`, რომელიც ინტეგრირდება თქვენს Elixir პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/build-insights/elixir">აგების ანალიტიკა</.localized_link> და <.localized_link href="/guides/features/test-insights/elixir">ტესტირების ანალიტიკა</.localized_link>. ეს სახელმძღვანელო გაგიწევთ ინსტალაციისა და კონფიგურაციის პროცესში.

პაკეტი მოითხოვს Elixir 1.18 ან უფრო ახალ ვერსიას. მას არ სჭირდება Tuist-ის ბრძანების ხაზის ინტერფეისი.

## 1. პროექტის შექმნა {#create-the-project}

შექმენით პროექტი Tuist-ის დაფაზე და აირჩიეთ **Mix (Elixir)** როგორც აგების სისტემა. მისი იდენტიფიკატორი, `account/project`, აკავშირებს თქვენს Mix პროექტს მასთან.

## 2. პაკეტის დამატება {#add-the-package}

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

`runtime: false` ტოვებს Tuist-ს თქვენი მომუშავე აპლიკაციის გარეთ. გააგრძელეთ <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir-ით დაწყება</.localized_link> ერთად კეშირების, აგებისა და ტესტირების ანალიტიკის კონფიგურირებისთვის. ქვემოთ მოცემული სექციები მოიცავს ავთენტიკაციისა და კონფიგურაციის დეტალებს.

## 3. თქვენი გუნდისა და უწყვეტი ინტეგრაციის ავთენტიკაცია {#authenticate}

ყველა წევრი ასრულებს შემდეგს, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
mix tuist.login
```

ის ხსნის ბრაუზერს და ელოდება თქვენს ავტორიზაციას. ბრაუზერის გარეშე შესასვლელად, გადაეცით თქვენი სერთიფიკატები:

```bash
mix tuist.login --email person@example.com --password secret
```

როდესაც იყენებთ თვითმასპინძელ ან ლოკალურ Tuist სერვერს, დააყენეთ მისი საბაზისო URL `mix.exs`-ში, ან გადაეცით ის `--url`-ით:

```bash
mix tuist.login --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის მართლწერის თანმიმდევრულობა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

GitHub Actions-ზე, CircleCI-სა და Bitrise-ზე, უწყვეტ ინტეგრაციას არ სჭირდება შესვლის ნაბიჯი. პირველად, როდესაც ამოცანა აგზავნის ანგარიშს, ის ცვლის პროვაიდერის OpenID Connect ტოკენს Tuist ტოკენზე. <.localized_link href="/guides/integrations/gitforge/github">მიამაგრეთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტს და GitHub Actions-ზე მიანიჭეთ სამუშაოს `id-token: write` ნებართვა:

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

ნებისმიერი სხვა OpenID Connect იდენტობის პროვაიდერთან, როგორიცაა Fly.io Machines, კონფიგურირებადი workload identity trust policy **Workload identities** სექციაში თქვენი ანგარიშის **Settings → Authentication** გვერდზე, რომელიც ანიჭებს CI წვდომას იმ ანგარიშის ყველა მიმდინარე და მომავალ პროექტზე. დააყენეთ `TUIST_OIDC_ACCOUNT` Tuist ანგარიშზე, რომელსაც ეკუთვნის პროექტი, და მიაწოდეთ ახლად გამოშვებული იდენტობის ტოკენი პოლიტიკის აუდიტორიით `TUIST_OIDC_TOKEN`-ის მეშვეობით. ინტეგრაცია ავტომატურად ცვლის მას, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან მოქმედი შენახული შესვლა; `mix tuist.login` ასევე იღებს მას CI-ს გარეთ. ავტომატური ცვლა იყენებს ხელუხლებელ სესიას მხოლოდ იმავე სერვერის, ანგარიშისა და მიწოდებული იდენტობის ტოკენისთვის. ამ იდენტობის შეცვლა იწვევს ახალ ცვლას, ხოლო ცარიელი მიწოდებული იდენტობა ვერ ხერხდება ადრეული სესიის ხელახლა გამოყენების ნაცვლად. Tuist სესიები გრძელდება ერთი საათი განახლების ტოკენების გარეშე, ამიტომ უფრო ხანგრძლივი სამუშაოებისთვის, გამოუშვით ახალი იდენტობის ტოკენი და გაუშვით `mix tuist.login` ხელახლა სესიის ამოწურვამდე. მიჰყევით <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">workload identity-ის კონფიგურაციას</.localized_link> და <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io-ს მაგალითს</.localized_link>.

Fork-ებიდან მოსული Pull Request-ები არ იღებენ OpenID Connect ტოკენს, ამიტომ მათი გაშვებები არ იგზავნება და ჩვეულებრივად გადიან ან ვერ გადიან. სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` გარემოს ცვლადი ანგარიშის ტოკენზე. მიჰყევით <.localized_link href="/guides/integrations/continuous-integration#authentication">უწყვეტი ინტეგრაციის ავთენტიკაციის სახელმძღვანელოს</.localized_link> ერთის შესაქმნელად.

## 4. განაგრძეთ `mix test`-ისა და `mix compile`-ის გამოყენება {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">საერთო კონფიგურაცია</.localized_link> აყენებს კომპილაციისა და ტესტირების ალიასებს თქვენთვის. `mix test test/my_app_test.exs:12 --trace` აგზავნის ანგარიშს იმავე გამომავალი მონაცემებითა და გასვლის კოდით, ხოლო კომპილაციის ინტეგრაცია მოიცავს აგებებს, რომლებიც გამოწვეულია `mix test`-ით ან `mix phx.server`-ით. კომპილაცია, რომელიც ვერ პოულობს გასაკეთებელს, არ იგზავნება.

ამოცანები ასევე მუშაობენ, როდესაც მათ საკუთარი სახელით იძახებთ. Mix-ი იწყებს ამოცანას, რომელიც ასეა დაწერილი `dev` გარემოში, ამიტომ ამოცანას უნდა დაიწყოს თავიდან მეორე პროცესში ტესტირების გარემოსთვის. დაამატეთ ამოცანები სასურველ გარემოებში ამის გამოსატოვებლად:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## კონფიგურაციის ცნობარი {#configuration-reference}

შემდეგი პარამეტრები ხელმისაწვდომია `tuist`-ის ქვეშ `mix.exs`-ის პროექტის პარამეტრებში:

| პარამეტრი | ტიპი | ნაგულისხმევი | აღწერა |
| --- | --- | --- | --- |
| `project` | `String` | არ არის (სავალდებულო) | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `url` | `String` | `"https://tuist.dev"` | Tuist სერვერის საბაზისო URL. |
| `cache` | `boolean` ან საკვანძო სიტყვების სია | გამორთული | კონფიგურაცია ააქტიურებს დამოკიდებულებების კეშირებას. იხილეთ <.localized_link href="/guides/features/cache/elixir">Elixir კეში</.localized_link> გამორიცხვებისა და დამატებითი შეყვანებისთვის. |
| `test_retries` | `integer` | `0` | რამდენჯერ უნდა განმეორდეს ჩავარდნილი ტესტები; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">ტესტის განმეორებები</.localized_link>. |
| `tags` | სია `String`-ის | `[]` | ტეგები, რომლებიც მიამაგრდება ყოველ აგებას; იხილეთ <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">მორგებული მეტამონაცემები</.localized_link>. |
| `values` | რუკა | `%{}` | საკვანძო-მნიშვნელობის მონაცემები, რომლებიც მიამაგრდება ყოველ აგებას. |

გარემოს ცვლადებს აქვთ უპირატესობა `mix.exs`-ზე:

| ცვლადი | აღწერა |
| --- | --- |
| `TUIST_PROJECT` | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `TUIST_URL` | Tuist სერვერის საბაზისო URL. |
| `TUIST_TOKEN` | ნიშანი ავტორიზაციისთვის, შენახული შესვლის ნაცვლად. |
| `TUIST_OIDC_TOKEN` | ახლად გენერირებული OpenID Connect იდენტობის ნიშანი, რომელიც იცვლება Tuist ნიშანზე. მისი აუდიენსია უნდა იყოს `tuist` GitHub Actions-ისა და Bitrise-ისთვის, ან ემთხვეოდეს პროექტის ნდობის პოლიტიკას სხვა მომწოდებლებისთვის. გამოიყენება `mix tuist.login`-ის მიერ ან როგორც სათადარიგო ვარიანტი, როდესაც არ არის ხელმისაწვდომი ანგარიშის ნიშანი ან მოქმედი შენახული შესვლა. |
| `TUIST_OIDC_ACCOUNT` | Tuist ანგარიშის სახელი, რომელიც ფლობს პროექტს. საჭიროა ნიშნის გაცვლისას პროექტის ნდობის პოლიტიკის მეშვეობით. ის ირჩევს არსებულ ნდობის პოლიტიკებს შორის და თავისთავად არ ანიჭებს წვდომას. |
| `TUIST_TEST_RETRIES` | რამდენჯერ უნდა განმეორდეს ჩავარდნილი ტესტები. |
| `TUIST_TAGS` | მძიმით გამოყოფილი ტეგები, რომლებიც მიამაგრდება აგებას. |
| `TUIST_VALUES` | მძიმით გამოყოფილი `key=value` წყვილები, რომლებიც მიამაგრდება აგებას. |
| `TUIST_DEBUG` | დააყენეთ `1`, რათა დაიბეჭდოს მიზეზი, თუ რატომ ვერ გაიგზავნა ანგარიში. |

ანგარიშგება არასდროს ცვლის `mix test`-ის ან `mix compile`-ის გამოსვლის კოდს. თუ ანგარიშის გაგზავნა შეუძლებელია, ამოცანა არაფერს ამბობს, თუ არ არის დაყენებული `TUIST_DEBUG=1`.

## შემდეგი ნაბიჯები {#next-steps}

პაკეტის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ გამოიყენოთ:

- <.localized_link href="/guides/features/cache/elixir">დამოკიდებულებების კეშირება</.localized_link> კომპილირებული დამოკიდებულებების ხელახლა გამოსაყენებლად ლოკალურად და CI აგებებში.
- <.localized_link href="/guides/features/build-insights/elixir">აგების ანალიტიკა</.localized_link> კომპილაციის დროის, გაფრთხილებებისა და აგების შემაფერხებელი ფაქტორების თვალყურის სადევნებლად.
- <.localized_link href="/guides/features/test-insights/elixir">ტესტების ანალიტიკა</.localized_link> ტესტების შესრულების თვალყურის სადევნებლად თითოეულ ტესტამდე.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">არასტაბილური ტესტები</.localized_link> დროდადრო ჩავარდნილი ტესტების აღმოჩენისა და თვალყურის სადევნებლად.
- <.localized_link href="/guides/features/test-sharding/elixir">ტესტების დაყოფა</.localized_link> თქვენი ტესტების გასანაწილებლად უწყვეტი ინტეგრაციის გამშვებებზე.
