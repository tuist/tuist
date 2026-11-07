---
{
  "title": "Docker",
  "titleTemplate": ":title · Runners · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Runners üzerinde Docker kullanın: konteyner oluşturun ve çalıştırın, konteyner işlerini, hizmet konteynerlerini ve özel kayıt defterlerini yönetin."
}
---
# Docker {#docker}

Linux çalıştırıcılar, kullanıma hazır Docker ile gelir. Her iş, sanal makinesi içinde kendi Docker daemon'una sahiptir ve `docker` CLI, Buildx ile Compose önceden yüklenmiştir. Bir kurulum eylemine veya `sudo` kullanımına ihtiyacınız yoktur.

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
> **Yalnızca Linux**
>
> macOS çalıştırıcılar bir Docker daemon sağlamaz. Buna ihtiyaç duyan işler için bir Linux <.localized_link href="/guides/features/runners/profiles">profilini</.localized_link> kullanın.

## Bir kapsayıcıda iş çalıştırma {#running-a-job-in-a-container}

İşinizin çalışması gereken imaja `container` yönlendirin. Tuist bu imajı çeker ve her adımı bunun içinde çalıştırır:

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

## Hizmet kapsayıcıları {#service-containers}

`services`, GitHub tarafından barındırılan çalıştırıcılardaki gibi çalışır. Hizmetlere, eşlenen portlarında `localhost` üzerinden erişilebilir:

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

## Özel kayıt defterleri {#private-registries}

Çekme veya itme işleminden önce, kayıt defterinin kendi giriş eylemiyle veya `docker login` ile kimlik doğrulaması yapın:

```yaml
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - run: docker pull ghcr.io/my-org/android-ci:latest
```

İş düzeyinde bir `container` için, yukarıdaki örnekte olduğu gibi aynı kimlik bilgilerini bunun yerine `credentials` anahtarı aracılığıyla iletin.

## İmaj çekme işlemleri {#image-pulls}

Docker Hub çekme işlemleri, Tuist tarafından işletilen bir geçişli önbellek üzerinden sunulur; böylece işler Docker Hub'ın anonim hız sınırını tüketmez. Diğer kayıt defterlerinden gelen imajlar doğrudan çekilir.

Her iş boş bir imaj deposuyla başlar, bu nedenle iş akışınızın kullandığı bir imaj işler arasında yeniden kullanılmak yerine iş başına bir kez çekilir. Bir iş büyük bir özel imaj çekiyorsa, imajı küçük tutun veya önbelleğe alınmış bir Buildx derleyicisiyle iş akışı içinde oluşturun:

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

Yerel işlerde veya kapsayıcı işlerinde kalıcı bağımlılık dizinleri için <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimleri kılavuzuna</.localized_link> bakın.
