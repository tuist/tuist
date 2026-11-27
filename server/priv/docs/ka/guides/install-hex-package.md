---
{
  "title": "Hex-პაკეტის ინსტალაცია",
  "titleTemplate": ":title · სახელმძღვანელოები · Tuist",
  "description": "გაიგეთ, როგორ დააინსტალიროთ და მოარგოთ Tuist-ის Hex-პაკეტი თქვენს Elixir პროექტში."
}
---
# Hex-პაკეტის ინსტალაცია {#install-the-hex-package}

Tuist გთავაზობთ [Hex](https://hex.pm/packages/tuist_ex)-პაკეტს, `tuist_ex`, რომელიც ინტეგრირდება თქვენს Elixir პროექტთან ისეთი ფუნქციების ჩასართავად, როგორიცაა <.localized_link href="/guides/features/build-insights/elixir">build insights</.localized_link> და <.localized_link href="/guides/features/test-insights/elixir">test insights</.localized_link>. ეს სახელმძღვანელო გაგიწევთ მის ინსტალაციასა და კონფიგურაციაში.

პაკეტი მოითხოვს Elixir 1.18 ან უფრო ახალ ვერსიას. მას არ სჭირდება Tuist ბრძანებების ხაზის ინტერფეისი (CLI).

## 1. შექმენით პროექტი {#create-the-project}

შექმენით პროექტი Tuist დაშბორდზე და აირჩიეთ **Mix (Elixir)** როგორც მისი ბილდის სისტემა. მისი იდენტიფიკატორი, `account/project`, აკავშირებს თქვენს Mix პროექტს მასთან.

## 2. დაამატეთ პაკეტი {#add-the-package}

დაამატეთ `tuist_ex` დამოკიდებულებებში თქვენს `mix.exs`-ში:

<!-- @snippet: ./_tuist-ex-dependency -->

შემდეგ ჩამოტვირთეთ ის:

```bash
mix deps.get
```

`runtime: false` ტოვებს Tuist-ს თქვენი გაშვებული აპლიკაციის გარეთ. გააგრძელეთ <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir-ის დაწყებით</.localized_link> ქეშირების, build insights-ისა და test insights-ის ერთად კონფიგურაციისთვის. ქვემოთ მოცემულ სექციებში განხილულია ავტორიზაციისა და კონფიგურაციის დეტალები.

## 3. ავტორიზაცია თქვენი გუნდისა და უწყვეტი ინტეგრაციისთვის {#authenticate}

ყველა წევრი ასრულებს შემდეგს, რათა მიიღოს წვდომა Tuist ფუნქციებზე თავის მანქანაზე:

```bash
mix tuist.login
```

ის ბეჭდავს მოკლე შესვლის კოდს, ხსნის ბრაუზერს, სადაც თქვენ შეჰყავთ ის და ელოდება თქვენს ავტორიზაციას. ბრაუზერის გარეშე შესასვლელად, გადაეცით თქვენი სარწმუნოებები:

```bash
mix tuist.login --email person@example.com --password secret
```

როდესაც იყენებთ self-hosted ან ლოკალურ Tuist სერვერს, დააყენეთ მისი საბაზო URL `mix.exs`-ში, ან გადაეცით ის `--url`-ით:

```bash
mix tuist.login --url http://localhost:8080
```

შეინახეთ ჰოსტნეიმის მართლწერა თანმიმდევრულად. მაგალითად, `localhost`-ისთვის შენახული შესვლა განცალკევებულია `127.0.0.1`-ისთვის შენახული შესვლისგან.

GitHub Actions-ზე, CircleCI-ზე და Bitrise-ზე, უწყვეტ ინტეგრაციას არ სჭირდება შესვლის ნაბიჯი. პირველად, როდესაც ამოცანა აგზავნის ანგარიშს, ის ცვლის პროვაიდერის OpenID Connect ტოკენს Tuist ტოკენზე. <.localized_link href="/guides/integrations/gitforge/github">დააკავშირეთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან და GitHub Actions-ზე მიანიჭეთ სამუშაოს `id-token: write` ნებართვა:

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

ნებისმიერი სხვა OpenID Connect იდენტობის პროვაიდერთან, მაგალითად Fly.io Machines, დააკონფიგურირეთ workload identity trust policy თქვენი ანგარიშის **Settings → Authentication** გვერდის **Workload identities** სექციაში, რაც CI-ს ანიჭებს წვდომას ამ ანგარიშის ყველა მიმდინარე და მომავალ პროექტზე. დააყენეთ `TUIST_OIDC_ACCOUNT` იმ Tuist ანგარიშზე, რომელსაც ეკუთვნის პროექტი, და მიეწოდეთ ახლად შექმნილი იდენტობის ტოკენი პოლიტიკის აუდიტორიით `TUIST_OIDC_TOKEN`-ის მეშვეობით. ინტეგრაცია ავტომატურად ცვლის მას, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან ვალიდური შენახული შესვლა; `mix tuist.login` ასევე იღებს მას CI-ს გარეთ. ავტომატური გაცვლები ხელახლა იყენებენ ვადის გაუსვლელ სესიას მხოლოდ იმავე სერვერის, ანგარიშისა და მიწოდებული იდენტობის ტოკენისთვის. ამ იდენტობის შეცვლა იწვევს ახალ გაცვლას, ხოლო ცარიელი მიწოდებული იდენტობა ვერდება ადრეული სესიის ხელახლა გამოყენების ნაცვლად. Tuist სესიები გრძელდება ერთი საათის განმავლობაში refresh token-ების გარეშე, ამიტომ ხანგრძლივად მომუშავე workload-ებისთვის, შექმენით ახალი იდენტობის ტოკენი და გაუშვით `mix tuist.login` ხელახლა სესიის ვადის გასვლამდე. მიჰყევით <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">workload identity-ის დაყენებას</.localized_link> და <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io მაგალითს</.localized_link>.

fork-ებიდან მოსულ pull request-ებს არ აქვთ OpenID Connect ტოკენი, ამიტომ მათი გაშვებები არ იგზავნება ანგარიშში და ჩვეულებრივად გადიან ან ვერდებიან. სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` გარემოს ცვლადი ანგარიშის ტოკენზე. მიჰყევით <.localized_link href="/guides/server/authentication#continuous-integration">უწყვეტი ინტეგრაციის ავტორიზაციის სახელმძღვანელოს</.localized_link> ერთის შესაქმნელად.

## 4. განაგრძეთ `mix test`-ისა და `mix compile`-ის გამოყენება {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">გაზიარებული დაყენება</.localized_link> ინსტალირებს კომპილაციისა და ტესტირების ალიასებს თქვენთვის. `mix test test/my_app_test.exs:12 --trace` აგზავნის ანგარიშს გაშვების შესახებ იმავე გამომავალი მონაცემებითა და გასვლის კოდით, ხოლო კომპილაციის ინტეგრაცია მოიცავს ბილდებს, რომლებიც გამოწვეულია `mix test`-ით ან `mix phx.server`-ით. კომპილაცია, რომელიც არ პოულობს გასაკეთებელს, არ იგზავნება ანგარიშში.

ამოცანები ასევე მუშაობენ, როდესაც მათ საკუთარი სახელით იძახებთ. Mix-ი ასეთად დაწერილ ამოცანას იწყებს `dev` გარემოში, ამიტომ ამოცანა უნდა დაიწყოს თავიდან მეორე პროცესში ტესტირების გარემოსთვის. დაამატეთ ამოცანები სასურველ გარემოებში ამის თავიდან ასაცილებლად:

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
| `url` | `String` | `"https://tuist.dev"` | Tuist სერვერის საბაზო URL. |
| `cache` | `boolean` ან keyword სია | გამორთული | დაყენება ააქტიურებს დამოკიდებულებების ქეშირებას. იხილეთ <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> გამონაკლისებისა და დამატებითი შეყვანებისთვის. |
| `test_retries` | `integer` | `0` | რამდენჯერ უნდა განმეორდეს ვერშეული ტესტები; იხილეთ <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">ტესტის განმეორებები</.localized_link>. |
| `tags` | `String`-ის სია | `[]` | ტეგები, რომლებიც მიებას ყოველ ბილდს; იხილეთ <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">მორგებული მეტამონაცემები</.localized_link>. |
| `values` | რუკა (map) | `%{}` | საწყის-მნიშვნელობის მონაცემები, რომლებიც მიებას ყოველ ბილდს. |

გარემოს ცვლადებს აქვთ უპირატესობა `mix.exs`-ზე:

| ცვლადი | აღწერა |
| --- | --- |
| `TUIST_PROJECT` | პროექტის იდენტიფიკატორი `account/project` ფორმატში. |
| `TUIST_URL` | Tuist სერვერის საბაზო URL. |
| `TUIST_TOKEN` | მარშრუტიზაციის ტოკენი ავტორიზაციისთვის, შენახული შესვლის ნაცვლად. |
| `TUIST_OIDC_TOKEN` | ახლად გამოშვებული OpenID Connect იდენტობის ტოკენი, რომელიც იცვლება Tuist ტოკენზე. მისი აუდიენსია უნდა იყოს `tuist` GitHub Actions-ისა და Bitrise-ისთვის, ან ემთხვეოდეს ანგარიშის სამუშაო იდენტობას სხვა პროვაიდერებისთვის. გამოიყენება `mix tuist.login`-ის მიერ ან როგორც ალტერნატივა, როდესაც არ არის ხელმისაწვდომი ანგარიშის ტოკენი ან ვალიდური შენახული შესვლა. |
| `TUIST_OIDC_ACCOUNT` | Tuist ანგარიშის handle, რომელიც ფლობს პროექტს. საჭიროა ტოკენის გაცვლისას ანგარიშის სამუშაო იდენტობის მეშვეობით. ის ირჩევს არსებულ სამუშაო იდენტობებს შორის და თავისთავად არ გასცემს წვდომას. |
| `TUIST_TEST_RETRIES` | რამდენჯერ უნდა განმეორდეს ვერშეული ტესტები. |
| `TUIST_TAGS` | მძიმით გამოყოფილი ტეგები, რომლებიც მიებას ბილდს. |
| `TUIST_VALUES` | მძიმით გამოყოფილი `key=value` წყვილები, რომლებიც მიებას ბილდს. |
| `TUIST_DEBUG` | დააყენეთ `1`, რათა დაიბეჭდოს მიზეზი, თუ რატომ ვერ გაიგზავნა ანგარიში. |

ანგარიშგება არასდროს ცვლის `mix test`-ის ან `mix compile`-ის გამოსვლის კოდს. თუ ანგარიშის გაგზავნა შეუძლებელია, ამოცანა არაფერს ამბობს, თუ არ არის დაყენებული `TUIST_DEBUG=1`.

## შემდეგი ნაბიჯები {#next-steps}

პაკეტის დაყენებისა და კონფიგურაციის შემდეგ, შეგიძლიათ გამოიყენოთ:

- <.localized_link href="/guides/features/cache/elixir">დამოკიდებულებების ქეშირება</.localized_link> კომპილირებული დამოკიდებულებების ხელახლა გამოსაყენებლად ლოკალურად და CI ბილდებში.
- <.localized_link href="/guides/features/build-insights/elixir">ბილდის ინსაიტები</.localized_link> კომპილაციის დროების, გაფრთხილებებისა და იმის თვალყურის დევნებისთვის, რაც აფერხებს თქვენს ბილდებს.
- <.localized_link href="/guides/features/test-insights/elixir">ტესტების ინსაიტები</.localized_link> ტესტების შესრულების თვალყურის დევნისთვის თითოეულ ტესტამდე.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">არასტაბილური ტესტები</.localized_link> პერიოდულად ვერშეული ტესტების აღმოჩენისა და თვალყურის დევნისთვის.
- <.localized_link href="/guides/features/test-sharding/elixir">ტესტების დაშლა</.localized_link> თქვენი ტესტების გასანაწილებლად უწყვეტი ინტეგრაციის გამშვებებზე.
