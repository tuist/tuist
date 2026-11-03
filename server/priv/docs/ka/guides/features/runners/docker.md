---
{
  "title": "Docker",
  "titleTemplate": ":title · გამშვები სერვერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გამოიყენეთ Docker Tuist-ის გამშვებ სერვერებზე: ააწყვეთ და გაუშვით კონტეინერები, კონტეინერული დავალებები, სერვისული კონტეინერები და პირადი რეესტრები."
}
---
# Docker {#docker}

Linux-ის რანერები მოდიან Docker-ით, რომელიც მზად არის გამოსაყენებლად. თითოეულ ჯობს აქვს საკუთარი Docker-ის დემონი ჯობის ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის ინსტალირებული. თქვენ არ გჭირდებათ setup-ის ექშენი და არ გჭირდებათ `sudo`.

```yaml
jobs:
  build:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t my-app .
      - run: docker run --rm my-app ./run-checks.sh
```

> [!NOTE]
> **მხოლოდ Linux-ზე**
>
> macOS-ის რანერები არ უზრუნველყოფენ Docker-ის დემონს. გამოიყენეთ Linux-ის <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ ჯობებისთვის, რომლებსაც ეს სჭირდებათ.

## ჯობის გაშვება კონტეინერში {#running-a-job-in-a-container}

მიმართეთ `container` იმ იმიჯზე, რომელშიც თქვენი ჯობა უნდა გაეშვას. Tuist ჩამოტვირთავს მას და ყოველ ნაბიჯს მის შიგნით გაუშვებს:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    container:
      image: ghcr.io/my-org/android-ci:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
      - run: ./gradlew test
```

## სერვისული კონტეინერები {#service-containers}

`services` მუშაობს ისევე, როგორც GitHub-ის მიერ განთავსებულ რანერებზე. სერვისები ხელმისაწვდომია `localhost`-ზე მათი შესაბამისი პორტების მეშვეობით:

```yaml
jobs:
  test:
    runs-on: tuist-linux
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - run: mix test
```

## პირადი რეესტრები {#private-registries}

ავთენტიფიცირდით რეესტრის საკუთარი login-ის ექშენით ან `docker login`-ით, სანამ ჩამოტვირთვას ან ატვირთვას შეასრულებთ:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

ჯობის დონის `container`-ისთვის, გადაეცით იგივე სერთიფიკატები `credentials` გასაღების მეშვეობით, როგორც ზემოთ მოცემულ მაგალითში.

## იმეჯების ჩამოტვირთვა {#image-pulls}

Docker Hub-ის ჩამოტვირთვები ხორციელდება pull-through ქეშის მეშვეობით, რომელსაც Tuist აწარმოებს, ამიტომ ჯობები არ ხარჯავენ Docker Hub-ის ანონიმური რეიტინგის ლიმიტს. სხვა რეესტრებიდან იმიჯები პირდაპირ ჩამოიტვირთება.

ყოველი ჯობა იწყება ცარიელი იმიჯების საცავით, ამიტომ თქვენი სამუშაო ნაკადის მიერ გამოყენებული იმიჯი ჩამოიტვირთება ერთხელ თითოეული ჯობისთვის და არ არის ხელახლა გამოყენებული ჯობებს შორის. თუ ჯობა ტვირთავს დიდ კუსტომ იმიჯს, შეინახეთ იმიჯი მცირე ზომის, ან ააშენეთ ის სამუშაო ნაკადში ქეშირებული Buildx ბილდერის გამოყენებით:

```yaml
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        with:
          context: .
          tags: my-app:latest
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

ნეიტიურ ან კონტეინერულ ჯობებში მუდმივი დამოკიდებულობების დირექტორიებისთვის, იხილეთ <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომების სახელმძღვანელო</.localized_link>.
