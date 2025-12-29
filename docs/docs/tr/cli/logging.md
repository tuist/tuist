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

## Günlükleri kullanarak sorunları teşhis etme {#diagnose-issues-using-logs}

Bir komut çağrısı istenen sonuçları vermezse, günlükleri inceleyerek sorunu
teşhis edebilirsiniz. CLI günlükleri
[OSLog](https://developer.apple.com/documentation/os/oslog) ve dosya sistemine
iletir.

Her çalıştırmada, `$XDG_STATE_HOME/tuist/logs/{uuid}.log` adresinde bir günlük
dosyası oluşturur; burada `$XDG_STATE_HOME`, ortam değişkeni ayarlanmamışsa
`~/.local/state` değerini alır. Tuist'e özgü bir durum dizini ayarlamak için
`$TUIST_XDG_STATE_HOME` adresini de kullanabilirsiniz; bu, `$XDG_STATE_HOME`
adresinden önceliklidir.

::: tip
<!-- -->
Tuist'in dizin organizasyonu ve özel dizinlerin nasıl yapılandırılacağı hakkında
daha fazla bilgiyi <LocalizedLink href="/cli/directories">Directories belgesinde</LocalizedLink> bulabilirsiniz.
<!-- -->
:::

Varsayılan olarak CLI, yürütme beklenmedik bir şekilde sona erdiğinde günlük
yolunun çıktısını verir. Çıkmazsa, günlükleri yukarıda belirtilen yolda
bulabilirsiniz (yani, en son günlük dosyası).

::: warning
<!-- -->
Hassas bilgiler redakte edilmez, bu nedenle günlükleri paylaşırken dikkatli
olun.
<!-- -->
:::

### Sürekli entegrasyon {#diagnose-issues-using-logs-ci}

Ortamların tek kullanımlık olduğu CI'da, CI işlem hattınızı Tuist günlüklerini
dışa aktaracak şekilde yapılandırmak isteyebilirsiniz. Yapıtların dışa
aktarılması CI hizmetlerinde ortak bir özelliktir ve yapılandırma kullandığınız
hizmete bağlıdır. Örneğin, GitHub Actions'ta günlükleri bir eser olarak yüklemek
için `actions/upload-artifact` eylemini kullanabilirsiniz:

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

Önbellekle ilgili sorunları ayıklamak için Tuist, `dev.tuist.cache` alt sistemi
ile `os_log` kullanarak önbellek daemon işlemlerini günlüğe kaydeder. Bu
günlükleri kullanarak gerçek zamanlı olarak yayınlayabilirsiniz:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Bu günlükler, `dev.tuist.cache` alt sistemi için filtreleme yapılarak
Console.app'de de görülebilir. Bu, önbellek yükleme, indirme ve iletişim
sorunlarını teşhis etmeye yardımcı olabilecek önbellek işlemleri hakkında
ayrıntılı bilgi sağlar.
