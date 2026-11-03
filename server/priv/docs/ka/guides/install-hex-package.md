---
{
  "title": "Hex პაკეტის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ დააინსტალიროთ და მოირგოთ Tuist-ის Hex პაკეტი თქვენს Elixir პროექტში."
}
---
# Hex პაკეტის ინსტალაცია {#install-the-hex-package}

Tuist გთავაზობთ [Hex](https://hex.pm/packages/tuist_ex) პაკეტს, `tuist_ex`, რომელიც ინტეგრირდება თქვენს Elixir პროექტთან და საშუალებას გაძლევთ გამოიყენოთ ისეთი ფუნქციები, როგორიცაა <.localized_link href="/guides/features/build-insights/elixir">build insights</.localized_link> და <.localized_link href="/guides/features/test-insights/elixir">test insights</.localized_link>. ეს სახელმძღვანელო გასწავლით მის ინსტალაციას და კონფიგურაციას.

პაკეტი მოითხოვს Elixir 1.18 ან უფრო ახალ ვერსიას. მას არ სჭირდება Tuist-ის ბრძანების ხაზის ინტერფეისი (CLI).

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

`runtime: false` ტოვებს Tuist-ს თქვენი გაშვებული აპლიკაციის გარეთ. გააგრძელეთ <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Get started with Elixir</.localized_link>-ით, რათა ერთად დააკონფიგურიროთ ქეშირება, build insights და test insights. ქვემოთ მოცემული სექციები აღწერს ავტორიზაციას და კონფიგურაციის დეტალებს.

## 3. დააავტორეთ თქვენი გუნდი და უწყვეტი ინტეგრაცია (CI) {#authenticate}

თითოეულმა თანაგუნდელმა უნდა შეასრულოს შემდეგი ბრძანება, რათა მიიღოს წვდომა Tuist-ის ფუნქციებზე თავის მანქანაზე:

```bash
mix tuist.login
```

ეს ხსნის ბრაუზერს და ელოდება თქვენს ავტორიზაციას. ბრაუზერის გარეშე შესასვლელად, გადაეცით თქვენი სარწმუნოებები:

```bash
mix tuist.login --email person@example.com --password secret
```

როდესაც იყენებთ თვითმასპინძელ ან ლოკალურ Tuist სერვერს, დააყენეთ მისი საბაზისო URL `mix.exs`-ში, ან გადაეცით ის `--url`-ით:

```bash
mix tuist.login --url http://localhost:8080
```

შეინარჩუნეთ ჰოსტის სახელის მართლწერის თანმიმდევრულობა. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

GitHub Actions-ზე, CircleCI-ზე და Bitrise-ზე, უწყვეტ ინტეგრაციას (CI) არ სჭირდება შესვლის ნაბიჯი. პირველად, როდესაც ამოცანა აგზავნის ანგარიშს, ის ცვლის პროვაიდერის OpenID Connect ტოკენს Tuist-ის ტოკენზე. <.localized_link href="/guides/integrations/gitforge/github">Connect your GitHub repository</.localized_link> თქვენს Tuist პროექტთან და GitHub Actions-ზე მიანიჭეთ სამუშაოს `id-token: write` ნებართვა:

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

ნებისმიერი სხვა OpenID Connect იდენტობის პროვაიდერთან, როგორიცაა Fly.io Machines, დააკონფიგურეთ workload identity trust policy თქვენი ანგარიშის **Settings → Authentication** გვერდის **Workload identities** სექციაში, რაც CI-ს ანიჭებს წვდომას იმ ანგარიშის მიერ ფლობილ ყველა მიმდინარე და მომავალ პროექტზე. დააყენეთ `TUIST_OIDC_ACCOUNT` Tuist ანგარიშზე, რომელიც ფლობს პროექტს, და მიეწოდეთ ახლად გამოსხივებული იდენტობის ტოკენი პოლიტიკის აუდიენციით `TUIST_OIDC_TOKEN`-ის მეშვეობით. ინტეგრაცია ავტომატურად ცვლის მას, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან მოქმედი შენახული შესვლა; `mix tuist.login` ასევე იღებს მას CI-ს გარეთ. ავტომატური გაცვლები ხელახლა იყენებენ ვადაგასულ სესიას მხოლოდ იმავე სერვერის, ანგარიშის და მიწოდებული იდენტობის ტოკენისთვის. იდენტობის შეცვლა იწვევს ახალ გაცვლას, ხოლო ცარიელი მიწოდებული იდენტობა იწვევს შეცდომას ადრეული სესიის ხელახლა გამოყენების ნაცვლად. Tuist სესიები გრძელდება ერთი საათის განმავლობაში განახლების ტოკენების გარეშე, ამიტომ ხანგრძლივად მომუშავე workload-ებისთვის, გამოსხივეთ ახალი იდენტობის ტოკენი და გაუშვით `mix tuist.login` ხელახლა სესიის ამოწურვამდე. მიჰყევით <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">workload identity setup</.localized_link> და <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io example</.localized_link>.

Fork-ებიდან შემოსულ pull requests-ებს არ აქვთ OpenID Connect ტოკენი, ამიტომ მათი გაშვებები არ იგზავნება და ჩვეულებრივად გადის ან ვერ გადის. სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` გარემოს ცვლადი ანგარიშის ტოკენზე. შექმენით ის <.localized_link href="/guides/integrations/continuous-integration#authentication">continuous integration authentication guide</.localized_link>-ის მიხედვით.

## 4. განაგრძეთ `mix test` და `mix compile` გამოყენება {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">shared setup</.localized_link> ინსტალირებს კომპილაციის და ტესტირების ალიასებს თქვენთვის. `mix test test/my_app_test.exs:12 --trace` აგზავნის ანგარიშს იმავე გამომავალი მონაცემებით და გასვლის კოდით, ხოლო კომპილაციის ინტეგრაცია ფარავს ბილდებს, რომლებიც გამოწვეულია `mix test`-ით ან `mix phx.server`-ით. კომპილაცია, რომელიც არ პოულობს შესასრულებელ სამუშაოს, არ იგზავნება.

ამოცანები ასევე მუშაობენ, როდესაც მათ საკუთარი სახელით იძახებთ. Mix იწყებს ამოცანას, რომელიც ასეა დაწერილი, `dev` გარემოში, ამიტომ ამოცანას უნდა დაიწყოს თავიდან მეორე პროცესში ტესტირების გარემოსთვის. დაამატეთ ამოცანები სასურველ გარემოებში, რათა გამოტოვოთ ეს:

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
| `cache` | `boolean` ან საკვანძო სიტყვების სია | გამორთულია | Setup ააქტიურებს დამოკიდებულებების ქეშირებას. იხილეთ <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> გამორიცხვებისა და დამატებითი შეყვანებისთვის. |
| `test_retries` | `integer` | `0` | რამდენჯერ უნდა განმეორდეს ვერ გასული ტესტები; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>. |
| `tags` | `String` სია | `[]` | ტეგები, რომლებიც მიებას ყოველ ბილდს; იხილეთ <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">custom metadata</.localized_link>. |
| `values` | რუკა (map) | `%{}` | საკვანძო-მნიშვნელობის მონაცემები, რომლებიც მიებას ყოველ ბილდს. |

გარემოს ცვლადებს აქვთ უპირატესობა `mix.exs`-ზე:

| ცვლადი | აღწერა |
| --- | --- |
| `TUIST_PROJECT` | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `TUIST_URL` | Tuist სერვერის საბაზისო URL. |
| `TUIST_TOKEN` | მარკირების ტოკენი, რომელიც გამოიყენება შესვლის ნაცვლად. |
| `TUIST_OIDC_TOKEN` | ახლად შექმნილი OpenID Connect იდენტობის ტოკენი, რომელიც იცვლება Tuist ტოკენზე. მისი აუდიენსია უნდა იყოს `tuist` GitHub Actions-ისა და Bitrise-ისთვის, ან ემთხვეოდეს პროექტის ნდობის პოლიტიკას სხვა პროვაიდერებისთვის. გამოიყენება `mix tuist.login`-ით ან როგორც ალტერნატივა, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან მოქმედი შესვლა. |
| `TUIST_OIDC_ACCOUNT` | Tuist ანგარიშის სახელი, რომელსაც ეკუთვნის პროექტი. საჭიროა ტოკენის გაცვლისას პროექტის ნდობის პოლიტიკის მეშვეობით. ის ირჩევს არსებულ ნდობის პოლიტიკებს შორის და თავისთავად არ ანიჭებს წვდომას. |
| `TUIST_TEST_RETRIES` | რამდენჯერ უნდა განმეორდეს ვერ გასული ტესტები. |
| `TUIST_TAGS` | მძიმით გამოყოფილი ტეგები, რომლებიც მიებას ბილდს. |
| `TUIST_VALUES` | მძიმით გამოყოფილი `key=value` წყვილები, რომლებიც მიებას ბილდს. |
| `TUIST_DEBUG` | დააყენეთ `1`, რათა დაიბეჭდოს მიზეზი, თუ რატომ ვერ გაიგზავნა ანგარიში. |

ანგარიშგება არასდროს ცვლის `mix test`-ის ან `mix compile`-ის გამოსვლის კოდს. თუ ანგარიშის გაგზავნა შეუძლებელია, ამოცანა არაფერს ამბობს, თუ არ არის დაყენებული `TUIST_DEBUG=1`.

## შემდეგი ნაბიჯები {#next-steps}

პაკეტის ინსტალაციისა და კონფიგურაციის შემდეგ, შეგიძლიათ გამოიყენოთ:

- <.localized_link href="/guides/features/cache/elixir">დამოკიდებულებების ქეშირება</.localized_link> კომპილირებული დამოკიდებულებების ხელახლა გამოყენებისთვის ლოკალურად და CI ბილდებში.
- <.localized_link href="/guides/features/build-insights/elixir">ბილდის ანალიტიკა</.localized_link> კომპილაციის დროის, გაფრთხილებების და ბილდების შემაფერხებელი ფაქტორების თვალყურის დევნებისთვის.
- <.localized_link href="/guides/features/test-insights/elixir">ტესტების ანალიტიკა</.localized_link> ტესტების შესრულების თვალყურის დევნისთვის თითოეულ ტესტამდე.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">არასტაბილური ტესტები</.localized_link> პერიოდულად მწყავი ტესტების აღმოჩენისა და თვალყურის დევნისთვის.
- <.localized_link href="/guides/features/test-sharding/elixir">ტესტების დაშლა</.localized_link> ტესტების გადანაწილებისთვის continuous integration რანერებზე.
