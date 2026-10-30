---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Use Docker on Tuist Runners: build and run containers, container jobs, service containers, and private registries."
}
---
# Docker {#docker}

Linux-ის გამშვები გარემოები მოდის Docker-ით, რომელიც მზადაა გამოყენებისთვის. თითოეულ სამუშაოს აქვს საკუთარი Docker დემონი ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის დაინსტალირებული. არ გჭირდებათ კონფიგურაციის ნაბიჯი და არც `sudo`.

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
> **მხოლოდ Linux-ისთვის**
>
> macOS-ის გამშვები გარემოები არ უზრუნველყოფენ Docker დემონს. გამოიყენეთ Linux-ის <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ სამუშაოებისთვის, რომლებსაც ეს სჭირდებათ.

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

`services` მუშაობს იმავე გზით, როგორც GitHub-ზე განთავსებულ გამშვებ გარემოებში. სერვისები ხელმისაწვდომია `localhost`-ზე მათ მიერ მითითებულ პორტებზე:

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

ავტორიზაცია გაიარეთ რეესტრის საკუთარი შესვლის ქმედებით, ან `docker login`-ით, სანამ ჩამოტვირთავთ ან ატვირთავთ:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

სამუშაოს დონის `container`-ისთვის, გადაეცით იგივე სერთიფიკატები `credentials` გასაღების მეშვეობით, როგორც ზემოთ მოცემულ მაგალითში.

## იმეჯების ჩამოტვირთვა {#image-pulls}

Docker Hub-ის ჩამოტვირთვები ხორციელდება Tuist-ის მიერ მართული cache-ის მეშვეობით, ამიტომ სამუშაოები არ ხარჯავენ Docker Hub-ის ანონიმური სიჩქარის ლიმიტს. სხვა რეესტრებიდან იმიჯები პირდაპირ ჩამოიტვირთება.

ყველა სამუშაო იწყება ცარიელი იმიჯების საცავით, ამიტომ თქვენი workflow-ის მიერ გამოყენებული იმიჯი ჩამოიტვირთება ერთხელ თითოეული სამუშაოსთვის და არა ხელახლა გამოიყენება სხვადასხვა სამუშაოებს შორის. თუ სამუშაო ჩამოტვირთავს დიდ კუსტომურ იმიჯს, შეინახეთ იმიჯი მცირე ზომის, ან ააგეთ ის workflow-ში cached Buildx ბილდერის გამოყენებით:

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

ნატიურ ან კონტეინერულ სამუშაოებში მუდმივი დამოკიდებულების დირექტორიებისთვის, იხილეთ <.localized_link href="/guides/features/runners/cache-volumes">cache volumes-ის სახელმძღვანელო</.localized_link>.
