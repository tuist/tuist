---
{
  "title": "Docker",
  "titleTemplate": ":title · გამშვები სერვერები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გამოიყენეთ Docker Tuist-ის გამშვებ სერვერებზე: ააწყვეთ და გაუშვით კონტეინერები, კონტეინერული დავალებები, მომსახურების კონტეინერები და პირადი რეესტრები."
}
---
# Docker {#docker}

Linux-ის რანერებზე Docker უკვე მზადაა გამოსაყენებლად. თითოეულ ჯობს საკუთარი Docker daemon ენიჭება ჯობის ვირტუალურ მანქანაში, ხოლო `docker` CLI, Buildx და Compose წინასწარ არის ინსტალირებული. არ გჭირდებათ setup action ან `sudo`.

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
> macOS-ის რანერები არ იძლევიან Docker daemon-ს. გამოიყენეთ Linux <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> იმ ჯობებისთვის, რომლებსაც ის სჭირდებათ.

## ჯობის კონტეინერში გაშვება {#running-a-job-in-a-container}

მიუთითეთ `container` იმ image-ზე, რომელშიც თქვენი ჯობა უნდა გაეშვას. Tuist ჩამოტვირთავს მას და ყველა ნაბიჯს მის შიგნით შეასრულებს:

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

`services` იგივენაირად მუშაობს, როგორც GitHub-ის მიერ განთავსებულ რანერებზე. სერვისები ხელმისაწვდომია `localhost`-ზე მათი მითითებული პორტებით:

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

ავტორიზაცია გაიარეთ რეესტრის საკუთარი login action-ით ან `docker login`-ით, სანამ image-ებს ჩამოტვირთავთ ან ატვირთავთ:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

ჯობის დონის `container`-ისთვის, გადაეცით იგივე სერთიფიკატები `credentials` გასაღების მეშვეობით, როგორც ეს ზემოთ მოყვანილ მაგალითშია.

## Image-ების ჩამოტვირთვა {#image-pulls}

Docker Hub-ის ჩამოტვირთვები ხდება pull-through cache-ის მეშვეობით, რომელსაც Tuist მართავს, ამიტომ ჯობები არ ხარჯავენ Docker Hub-ის ანონიმური მომხმარებლებისთვის დაწესებულ ლიმიტს. სხვა რეესტრებიდან image-ები პირდაპირ იტვირთება.

ყოველი ჯობა ცარიელი image store-ით იწყება, ამიტომ თქვენი workflow-ის მიერ გამოყენებული image ერთხელ იტვირთება თითოეული ჯობისთვის და არ გამოიყენება ჯობებს შორის. თუ ჯობა დიდ კუსტუმ image-ს ტვირთავს, შეინახეთ image მცირე ზომის, ან ააწყვეთ ის workflow-ში cached Buildx builder-ის გამოყენებით:

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
