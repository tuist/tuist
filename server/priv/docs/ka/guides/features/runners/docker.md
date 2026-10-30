---
{
  "title": "Docker",
  "titleTemplate": ":title · გამშვები სერვერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გამოიყენეთ Docker Tuist-ის გამშვებ სერვერებზე: ააწყვეთ და გაუშვით კონტეინერები, კონტეინერული სამუშაოები, სერვისული კონტეინერები და პირადი რეესტრები."
}
---
# Docker {#docker}

Linux-ის გამშვებები მოდის Docker-ით, რომელიც მზადაა გამოყენებისთვის. თითოეულ სამუშაოს აქვს საკუთარი Docker დემონი სამუშაოს ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის დაინსტალირებული. თქვენ არ გჭირდებათ setup action და არ გჭირდებათ `sudo`.

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
> macOS-ის გამშვებები არ უზრუნველყოფენ Docker დემონს. გამოიყენეთ Linux <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ სამუშაოებისთვის, რომლებსაც ის სჭირდებათ.

## სამუშაოს კონტეინერში გაშვება {#running-a-job-in-a-container}

მიმართეთ `container` იმ იმიჯზე, რომელშიც თქვენი სამუშაო უნდა შესრულდეს. Tuist ჩამოტვირთავს მას და შეასრულებს ყველა ნაბიჯს მის შიგნით:

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

`services` მუშაობს იმავე გზით, როგორც GitHub-ის მიერ განთავსებულ გამშვებებზე. სერვისები ხელმისაწვდომია `localhost`-ზე მათ მიერ მიბმულ პორტებზე:

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

სამუშაოს დონის `container`-ისთვის, გადაეცით იგივე სერთიფიკატები `credentials` გასაღების მეშვეობით, როგორც ზემოთ მოცემულ მაგალითში.

## იმედების ჩამოტვირთვა {#image-pulls}

Docker Hub-ის ჩამოტვირთვები ემსახურება pull-through cache-ის მეშვეობით, რომელსაც Tuist ახორციელებს, ამიტომ სამუშაოები არ ხარჯავენ Docker Hub-ის ანონიმური სიჩქარის ლიმიტს. სხვა რეესტრებიდან იმიჯები პირდაპირ იტვირთება.

ყოველი სამუშაო იწყება ცარიელი იმიჯების საცავით, ამიტომ თქვენი workflow-ის მიერ გამოყენებული იმიჯი ერთხელ იტვირთება თითოეული სამუშაოსთვის და არ გამოიყენება ხელახლა სამუშაოებს შორის. თუ სამუშაო ტვირთავს დიდ მორგებულ იმიჯს, შეინახეთ იმიჯი მცირე ზომის, ან ააშენეთ ის workflow-ში cached Buildx builder-ის გამოყენებით:

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

მშობლიურ სამუშაოებში ან კონტეინერულ სამუშაოებში მუდმივი დამოკიდებულების საქაღალდეებისთვის, იხილეთ <.localized_link href="/guides/features/runners/cache-volumes">cache volumes guide</.localized_link>.
