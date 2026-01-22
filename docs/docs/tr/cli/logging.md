---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Loglama {#logging}

CLI, sorunları teşhis etmenize yardımcı olmak için mesajları dahili olarak
günlüğe kaydeder.

## Günlükleri kullanarak sorunları teşhis edin {#diagnose-issues-using-logs}

Bir komut çağrısı istenen sonuçları vermezse, günlükleri inceleyerek sorunu
teşhis edebilirsiniz. CLI, günlükleri
[OSLog](https://developer.apple.com/documentation/os/oslog) ve dosya sistemine
iletir.

Her çalıştırmada, `$XDG_STATE_HOME/tuist/logs/{uuid}.log` adresinde bir günlük
dosyası oluşturur. Burada `$XDG_STATE_HOME`, ortam değişkeni ayarlanmamışsa
`~/.local/state` değerini alır. Ayrıca, `$TUIST_XDG_STATE_HOME` kullanarak
Tuist'e özgü bir durum dizini ayarlayabilirsiniz. Bu dizin, `$XDG_STATE_HOME`
dizininden önceliklidir.

::: tip
<!-- -->
Tuist'in dizin düzenlemesi ve <LocalizedLink href="/cli/directories">Dizinler
belgelerinde</LocalizedLink> özel dizinleri nasıl yapılandıracağınız hakkında
daha fazla bilgi edinin.
<!-- -->
:::

Varsayılan olarak, CLI, yürütme beklenmedik bir şekilde sonlandığında günlük
dosyalarının yolunu görüntüler. Aksi takdirde, günlükleri yukarıda belirtilen
yolda (yani en son günlük dosyasında) bulabilirsiniz.

::: warning
<!-- -->
Hassas bilgiler sansürlenmez, bu nedenle günlükleri paylaşırken dikkatli olun.
<!-- -->
:::

### Sürekli entegrasyon {#diagnose-issues-using-logs-ci}

Ortamların tek kullanımlık olduğu CI'da, CI ardışık düzeninizi Tuist
günlüklerini dışa aktarmak için yapılandırmak isteyebilirsiniz. Artefaktları
dışa aktarma, CI hizmetlerinde yaygın bir özelliktir ve yapılandırma,
kullandığınız hizmete bağlıdır. Örneğin, GitHub Actions'ta, günlükleri bir
artefakt olarak yüklemek için `actions/upload-artifact` eylemini
kullanabilirsiniz:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### Önbellek daemon hata ayıklama {#cache-daemon-debugging}

Önbellek ile ilgili sorunları gidermek için Tuist, `os_log` alt sistemi
`dev.tuist.cache` kullanarak önbellek daemon işlemlerini günlüğe kaydeder. Bu
günlükleri şu komutla gerçek zamanlı olarak aktarabilirsiniz:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Bu günlükler, `dev.tuist.cache` alt sistemi için filtreleme yapılarak
Console.app'te de görüntülenebilir. Bu, önbellek işlemleri hakkında ayrıntılı
bilgi sağlar ve önbellek yükleme, indirme ve iletişim sorunlarının teşhis
edilmesine yardımcı olabilir.
