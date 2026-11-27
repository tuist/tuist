---
{
  "title": "Docker",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გამოიყენეთ Docker Tuist-ის გამშვებებზე: ააწყვეთ და გაუშვით კონტეინერები, კონტეინერული სამუშაოები, სერვისული კონტეინერები და პირადი რეესტრები."
}
---
# Docker {#docker}

Linux-ის რანერები Docker-ით მოდის, მზად გამოყენებისთვის. თითოეულ ჯობს საკუთარი Docker daemon აქვს ჯობის ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის ინსტალირებული. არ გჭირდებათ setup action და არც `sudo`.

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
> **მხოლოდ Linux**
>
> macOS რანერები Docker daemon-ს არ უზრუნველყოფენ. გამოიყენეთ Linux <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ ჯობებისთვის, რომლებსაც ის სჭირდებათ.

## ჯობის კონტეინერში გაშვება {#running-a-job-in-a-container}

მიმართეთ `container` იმ გამოსახულებაზე, რომელშიც თქვენი ჯობა უნდა გაეშვას. Tuist მას ჩამოიტვირთავს და ყველა ნაბიჯს მის შიგნით შეასრულებს:

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

`services` მუშაობს იმავე გზით, როგორც GitHub-ის მიერ განთავსებულ რანერებზე. სერვისები ხელმისაწვდომია `localhost`-ზე მათ შესაბამის პორტებზე:

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

ავთენტიკაცია გაიარეთ რეესტრის საკუთარი login action-ით, ან `docker login`-ით, სანამ ჩამოტვირთავთ ან ატვირთავთ:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

ჯობის დონის `container`-ისთვის, გადასცეთ იგივე მონაცემები `credentials` გასაღების მეშვეობით, როგორც ზემოთ მოცემულ მაგალითში.

## გამოსახულებების ჩამოტვირთვა {#image-pulls}

Docker Hub-დან ჩამოტვირთვები ხორციელდება pull-through cache-ის მეშვეობით, რომელსაც Tuist მართავს, ამიტომ ჯობები არ ხარჯავენ Docker Hub-ის ანონიმური სიჩქარის ლიმიტს. სხვა რეესტრებიდან გამოსახულებები პირდაპირ იტვირთება.

ყოველი ჯობა ცარიელი გამოსახულებების საცავით იწყება, ამიტომ თქვენი workflow-ის მიერ გამოყენებული გამოსახულება ერთხელ იტვირთება თითოეული ჯობისთვის და არ გამოიყენება ჯობებს შორის. თუ ჯობა დიდ მორგებულ გამოსახულებას ტვირთავს, შეინახეთ გამოსახულება მცირე ზომის, ან ააშენეთ ის workflow-ში cached Buildx builder-ის გამოყენებით:

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

ნატიური ჯობების ან კონტეინერული ჯობებისთვის მუდმივი დამოკიდებულობების საქაღალდეების შესახებ, იხილეთ <.localized_link href="/guides/features/runners/cache-volumes">cache volumes guide</.localized_link>.
