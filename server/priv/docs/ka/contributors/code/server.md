---
{
  "title": "სერვერი",
  "titleTemplate": ":title · კოდი · კონტრიბუტორები · Tuist",
  "description": "შეიტანეთ წვლილი Tuist Server-ის განვითარებაში."
}
---
# სერვერი {#server}

წყარო: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## რისთვისაა საჭირო {#what-it-is-for}

სერვერი უზრუნველყოფს Tuist-ის სერვერულ ფუნქციებს, როგორიცაა ავთენტიკაცია, ანგარიშები და პროექტები, ქეშის შენახვა, ინსაიტები, პრივიუები, რეესტრი და ინტეგრაციები (GitHub, Slack და SSO). ეს არის Phoenix/Elixir აპლიკაცია Postgres-ით და ClickHouse-ით.

## როგორ შევუწყოთ ხელი {#how-to-contribute}

სერვერში წვლილის შეტანა მოითხოვს CLA-ზე ხელმოწერას (`server/CLA.md`).

### ლოკალურად განლაგება {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

გახსენით `http://localhost:8080` თქვენს ბრაუზერში. დეველოპმენტის რეჟიმში, შესვლის გვერდი შეიცავს **შესვლა სატესტო მომხმარებლით** ღილაკს, რომელიც გაგიმართლებთ წინასწარ შექმნილ ანგარიშზე (`tuistrocks@tuist.dev` / `tuistrocks`).

> [!NOTE]
> პირველხარისხოვანი დეველოპერები იღებენ დევის საიდუმლოებებს 1Password-დან fnox-ის მეშვეობით — `mise run dev` ახვევს სერვერს `fnox exec`-ში (იხილეთ `server/fnox.toml`). გარე კონტრიბუტორებს არ სჭირდებათ 1Password-ზე წვდომა; სერვერი ლოკალურად მუშაობს მის გარეშე. OAuth, Stripe და სხვა მესამე მხარის ინტეგრაციები იქნება გამორთული, მაგრამ ძირითადი ფუნქციონალი მუშაობს.

### ლოკალური Helm ტესტირება {#local-helm-testing}

თქვენ შეგიძლიათ აამუშაოთ სრული სტეკი თქვენს მანქანაზე [kind](https://kind.sigs.k8s.io/)-ის და ჩართული mise ამოცანების გამოყენებით. ეს აწყობს Docker იმიჯებს ლოკალურად, ქმნის kind კლასტერს, აყენებს chart-ს და ავტომატურად აკეთებს პორტების გადამისამართებას ყველა სერვისისთვის:

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**წინაპირობები:** `docker`, `kind`, `helm` და `kubectl`.

### ტესტები და ფორმატირება {#tests-and-formatting}

- ტესტები: `mix test`
- ფორმატი: `mise run format`
