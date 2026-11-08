---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გამოიყენეთ Docker Tuist Runners-ზე: ააწყვეთ და გაუშვით კონტეინერები, კონტეინერული დავალებები, სერვისის კონტეინერები და პირადი რეესტრები."
}
---
# Docker {#docker}

Linux-ის რანერები მოდის Docker-ით, რომელიც მზადაა გამოსაყენებლად. თითოეულ ჯობს აქვს საკუთარი Docker daemon ჯობის ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის დაინსტალირებული. არ გჭირდებათ setup action და არ გჭირდებათ `sudo`.

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
> macOS-ის რანერები არ უზრუნველყოფენ Docker daemon-ს. გამოიყენეთ Linux <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ ჯობებისთვის, რომლებსაც ეს სჭირდებათ.

## ჯობის კონტეინერში გაშვება {#running-a-job-in-a-container}

მიუთითეთ `container` იმაზე, რომელ სურათშიც უნდა გაეშვას თქვენი ჯობა. Tuist ჩამოტვირთავს მას და ყველა ნაბიჯს მის შიგნით შეასრულებს:

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

`services` მუშაობს ისევე, როგორც GitHub-ზე განთავსებულ რანერებზე. სერვისები ხელმისაწვდომია `localhost`-ზე მათ შესაბამის პორტებზე:

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

ავტორიზაცია გაიარეთ რეესტრის საკუთარი login action-ით, ან `docker login`-ით, სანამ სურათებს ჩამოტვირთავთ ან ატვირთავთ:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

ჯობის დონის `container`-ისთვის, გადასცეთ იგივე მონაცემები `credentials` გასაღების მეშვეობით, როგორც ზემოთ მოყვანილ მაგალითში.

## სურათების ჩამოტვირთვა {#image-pulls}

Docker Hub-ის ჩამოტვირთვები მიეწოდება pull-through cache-ის მეშვეობით, რომელსაც Tuist მართავს, ამიტომ ჯობები არ ხარჯავენ Docker Hub-ის ანონიმური მოხმარების ლიმიტს. სურათები სხვა რეესტრებიდან პირდაპირ იტვირთება.

ყველა ჯობა იწყება ცარიელი სურათების საცავით, ამიტომ თქვენი workflow-ის მიერ გამოყენებული სურათი თითოეული ჯობისთვის ერთხელ იტვირთება და არა გამოიყენება ჯობებს შორის. თუ ჯობა ტვირთავს დიდ მორგებულ სურათს, შეინახეთ სურათი მცირე ზომის, ან ააშენეთ ის workflow-ში cached Buildx builder-ის გამოყენებით:

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

მუდმივი დამოკიდებულობების დირექტორიებისთვის native ან კონტეინერულ ჯობებში, იხილეთ <.localized_link href="/guides/features/runners/cache-volumes">cache volumes-ის სახელმძღვანელო</.localized_link>.
