---
{
  "title": "Hata Ayıklama",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Günlük kayıtları ve ağ kayıtlarını kullanarak Tuist ile ilgili sorunları nasıl hata ayıklayacağınızı öğrenin."
}
---
# Hata Ayıklama {#debugging}

Tuist, komutların beklendiği gibi davranmadığı durumlarda sorunları teşhis etmenize yardımcı olacak birkaç araç sunar.

> [!WARNING]
> Oturum verileri; dosya yolları, proje adları ve istek/yanıt gövdeleri gibi hassas bilgiler içerebilir. Hassas başlıklar (örneğin Authorization) gizlense de oturum verilerini başkalarıyla paylaşırken dikkatli olun.


## Oturum verileri {#session-data}

Bir komut çağrısı beklenen sonuçları vermezse, oturum verilerini inceleyerek sorunu teşhis edebilirsiniz. CLI günlükleri [OSLog](https://developer.apple.com/documentation/os/oslog) ve dosya sistemine iletir.

Her çalıştırmada, `$XDG_STATE_HOME` ortam değişkeni ayarlanmamışsa `~/.local/state` değerini alan `$XDG_STATE_HOME/tuist/sessions/{uuid}/` konumunda bir oturum dizini oluşturur. Tuist’e özel bir durum dizini ayarlamak için `$TUIST_XDG_STATE_HOME` kullanabilirsiniz; bu değişken `$XDG_STATE_HOME` üzerinde önceliklidir.

Her oturum dizini şunları içerir:
- **`logs.txt`** - CLI oturumundan metin günlükleri
- **`network.har`** - Oturum sırasında yapılan tüm ağ isteklerini ve yanıtlarını içeren [HTTP Archive (HAR)](https://w3c.github.io/web-performance/specs/HAR/Overview.html) dosyası

### HAR dosyalarını görselleştirme {#visualizing-har-files}

HAR dosyası, oturum sırasında yapılan tüm HTTP isteklerini ve yanıtlarını kaydeder; bu, sunucu iletişim sorunlarını hata ayıklamak için yararlıdır. HAR dosyalarını birkaç araçla açabilirsiniz:

- **[Proxyman](https://proxyman.io/)**: HTTP trafiğini görüntülemek ve analiz etmek için yerel bir macOS uygulaması. HAR dosyasını Dosya > İçe Aktar yoluyla içe aktarın.
- **Tarayıcı Geliştirici Araçları**: Chrome, Firefox ve Safari, Ağ sekmesinde HAR dosyalarını içe aktarmayı destekler.
- **[HAR Viewer](http://www.softwareishard.com/har/viewer/)**: Web tabanlı bir HAR dosyası görüntüleyici.

> [!TIP]
> Tuist’in dizin düzeni ve özel dizinlerin nasıl yapılandırılacağı hakkında daha fazla bilgiyi <.localized_link href="/cli/directories">Dizinler belgelerinde</.localized_link> bulabilirsiniz.


Varsayılan olarak, CLI yürütme beklenmedik şekilde sonlandığında oturum yolunu çıktılar. Çıktılamazsa, oturum verilerini yukarıda belirtilen yolda (yani en son oturum dizininde) bulabilirsiniz.

5 günden eski oturum dizinleri otomatik olarak temizlenir. Tuist ayrıca varsayılan olarak en fazla 50 etkin olmayan oturum dizinini tutar ve şu anda çalışan Tuist süreçlerine ait oturumları korur. Aynı durum diziniyle çok sayıda Tuist komutu çalıştıran CI ortamlarında, etkin olmayan oturum sınırını `TUIST_SESSION_MAX_SESSIONS` ile artırabilirsiniz; örneğin `TUIST_SESSION_MAX_SESSIONS=200`. Geçersiz değerler, sıfır ve negatif değerler yoksayılır ve Tuist varsayılan 50 değerine geri döner.

### Sürekli entegrasyon {#diagnose-issues-using-logs-ci}

Ortamların geçici olduğu CI’da, Tuist oturum verilerini dışa aktarmak için CI hattınızı yapılandırmak isteyebilirsiniz. Yapıtları dışa aktarmak, CI hizmetlerinde yaygın bir yetenektir ve yapılandırma kullandığınız hizmete bağlıdır. Örneğin, GitHub Actions’da oturum verilerini bir yapıt olarak yüklemek için `actions/upload-artifact` eylemini kullanabilirsiniz:

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
      - name: Export Tuist session data
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-sessions
          path: /tmp/tuist/sessions/
```

### Xcode önbelleği hata ayıklama {#cache-daemon-debugging}

Xcode önbelleği sorunlarını hata ayıklamak için, hem `tuist setup cache` çalıştırırken hem de derleme yaparken `TUIST_CAS_LOG` değerini bir dosya yoluna ayarlayın. Tuist, önbellek istatistiklerini ve hataları bu dosyaya ekler:

```bash
export TUIST_CAS_LOG=$HOME/.local/state/tuist/cas.log
tuist setup cache
xcodebuild build -scheme YourScheme
```

CI’da Tuist, herhangi bir yapılandırma olmadan bu günlüğü `~/.local/state/tuist/cas.log` konumuna yazar.

## Ağ zaman aşımlarını ve yeniden denemeleri ayarlama {#tuning-network-timeouts}

Sunucu çağrıları, kayıt defteri, önizlemeler ve önbellek yapıtı aktarımları dahil olmak üzere Tuist’in tüm [Hypertext Transfer Protocol (HTTP)](https://developer.mozilla.org/en-US/docs/Web/HTTP) trafiği, makul varsayılanlara sahip paylaşılan bir `URLSession` üzerinden geçer. Yavaş veya tıkanık ağ yollarında (örneğin, kurumsal bir proxy üzerinden nesne depolamaya ulaşan kendi kendine barındırılan bir kurulum), tek bir istek kaynak yetersizliği yaşayabilir ve tamamlanmadan önce kaynak zaman aşımına uğrayabilir. Özellikle önbellek indirmelerinde, zaman aşımına uğramak Tuist’in modülü kaynaktan derlemeye geri dönmesine neden olur; bu da önbelleğe alınmış ikili dosya için biraz daha uzun beklemekten çok daha maliyetlidir. Altta yatan ayarları ortam değişkenleri aracılığıyla ayarlayabilirsiniz; değişkenler ayarlanmamışsa veya geçersiz bir değere ayarlanmışsa varsayılanlar uygulanır:

```bash
# Maximum time (in seconds) a single resource transfer can take before it's cancelled
# (default: 90, or 600 for whole-file transfers such as test-product shard artifacts)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE=600

# Maximum time (in seconds) to wait for new data on an existing request (default: 120)
export TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST=300

# Maximum number of simultaneous connections per host (default: 20)
export TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST=40

# Maximum retries after the initial attempt (default: 3, maximum: 10)
export TUIST_HTTP_MAXIMUM_RETRY_COUNT=1

# Initial exponential backoff delay in milliseconds (default: 100, maximum: 30000)
export TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS=250
```

Kaynak zaman aşımı, tüm aktarım için duvar saati tabanlı bir üst sınırdır, takılma koruması değildir; bu nedenle taşındığınız en büyük yapıt için yeterince büyük olmalıdır. Bir parçanın indirdiği test ürünleri gibi tüm dosya aktarımları bu nedenle 90 saniye yerine varsayılan olarak 10 dakikadır ve yeni veri gelmediğinde takılan bir aktarım yine de `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST` sonrasında başarısız olur. Bu aktarımlar, üst sınırı yalnızca yükseltmek için `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` değerini okur; bunu asla 10 dakikanın altına düşürmez. Böylece önbellek isteklerinin hızlı başarısız olması için seçilen bir değer, bir parçanın test ürünlerini indirmesini de iptal etmez. `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` değerini yükseltmek, kurtarılabilir ancak yavaş bir indirmenin zaman aşımına uğramak yerine tamamlanmasını sağlar. Önbellek indirmeleri için bu, kaynaktan derlemeye geri dönmek yerine bir önbellek isabeti elde etmek anlamına gelir; bu nedenle değeri bilinçli olarak yükseltin: yavaş bir önbellek indirmesini canlı tutan aynı değer, kaynaktan derlemeye geri dönüşü de geciktirir. `TUIST_HTTP_MAXIMUM_RETRY_COUNT` değerini düşürmek, daha uzun bir zaman aşımının en kötü durum bekleme süresini birkaç deneme boyunca çarpmasını engelleyebilir. Yeniden deneme gecikmeleri her başarısızlıktan sonra iki katına çıkar, en fazla bir temel gecikme kadar rastgele titreme içerir ve asla 30 saniyeyi aşmaz.

## Özel bir CA sertifikasına güvenme {#trusting-a-custom-ca-certificate}

Varsayılan olarak Tuist, TLS sertifikalarını işletim sisteminin kök deposuna göre doğrular. Özel bir sertifika yetkilisi kullanan kendi kendine barındırılan bir Tuist veya Kura sunucusu çalıştırdığınızda, Tuist’in bu CA’ya da güvenmesi gerekir. Kökü Sistem anahtar zincirine yüklemek (ve SSL için güvenilir olarak işaretlemek) standart yaklaşımdır; ancak GUI oturumu veya güven bitini ayarlayacak mobil cihaz yönetimi (MDM) bulunmayan headless CI ana bilgisayarlarında bu genellikle pratik değildir.

Bu durumlarda Tuist’i doğrudan bir CA sertifika paketine yönlendirebilirsiniz. Paket PEM (bir veya daha fazla bitişik `-----BEGIN CERTIFICATE-----` bloğu) veya tek bir DER dosyası olabilir. Sistem kök deposu bunun yanında güvenilir kalır, böylece genel sertifikalar normal şekilde doğrulanmaya devam eder ve sertifika değerlendirmesi asla atlanmaz.

```bash
# Path to a PEM/DER CA bundle to trust on top of the system root store (default: unset)
export TUIST_CA_CERTIFICATE=/etc/ssl/certs/self-hosted-ca.pem
```

Bunu <.localized_link href="/references/tuist-toml">yapılandırma dosyanızda</.localized_link> da belirtebilirsiniz:

```toml
[network]
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

`TUIST_CA_CERTIFICATE` ortam değişkeni yapılandırma dosyasına göre önceliklidir; bu da taahhüt edilen bildirimi değiştirmeden bir CI gizli değeri olarak sağlamanızı kolaylaştırır.
