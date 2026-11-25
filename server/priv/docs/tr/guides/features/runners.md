---
{
  "title": "Çalıştırıcılar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcıları, GitHub Actions, Buildkite, GitLab CI ve Bitrise için yönetilen macOS ve Linux çalıştırıcılardır; önbellek, hesaplama birimlerinin yanında konumlandırılır ve yerel makinelerinizle paylaşılır."
}
---
# Çalıştırıcılar {#runners}

Tuist Çalıştırıcıları, GitHub Actions, Buildkite, GitLab CI ve Bitrise pipeline’larınız için yönetilen macOS ve Linux çalıştırıcılardır. İşleri CI sağlayıcınızın barındırdığı makinelerde çalıştırmak yerine, bir işi bir Tuist <.localized_link href="/guides/features/runners/profiles">profiline</.localized_link> yönlendirirsiniz; iş Tuist’in filosunda, ekibinizin zaten kullandığı aynı <.localized_link href="/guides/features/cache">önbelleğin</.localized_link> yanında çalışır. Kurulması gereken bir çalıştırıcı aracısı veya bakımını yapmanız gereken bir altyapı yoktur. Makineleri değiştirmeden önce CI faturanızı neyin belirlediğini anlamak için [CI maliyetlerine](https://tuist.dev/solutions/ci-costs) bakın.

Benimsemek genellikle bir işte tek satırlık bir değişikliktir:

::: code-group

```diff [GitHub Actions]
 jobs:
   build:
-    runs-on: macos-latest
+    runs-on: tuist-macos
     steps:
       - uses: actions/checkout@v4
       - run: tuist test
```

```diff [Buildkite]
 steps:
   - label: "Test"
     command: tuist test
     agents:
-      queue: macos
+      queue: tuist-macos
```
<!-- -->
:::

## Linux üzerinde Android emülatörleri {#android-emulators}

Linux çalıştırıcıları varsayılan olarak `/dev/kvm` üzerinden donanım hızlandırmalı sanallaştırma sağlar. Gradle Yönetilen Cihazlar dahil x86_64 Android emülatörlerini çalıştırmak için olağan Linux <.localized_link href="/guides/features/runners/profiles">profilinizi</.localized_link>, örneğin `tuist-linux`, kullanın. Cihaza erişmek için özel bir çalıştırıcı profili, KVM kurulum eylemi, izin değişikliği veya `sudo` gerekmez.

Çalıştırıcı imajı Android SDK’yı içerir. Bir cihazı başlatmadan önce emülatörü ve çalışma zamanı kütüphanelerini yükleyin. Zaten `pixel6` adlı bir Gradle Yönetilen Cihaz tanımlayan bir proje için GitHub Actions işi şu şekilde görünür:

```yaml
jobs:
  android-test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - name: Install emulator dependencies
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends \
            libx11-6 libxcomposite1 libxcursor1 libxi6 libxtst6 libxrandr2 \
            libxrender1 libpulse0 libnss3 libxkbcommon-x11-0 libxcb-cursor0 \
            libasound2 libglu1-mesa
          "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" 'emulator'
      - name: Check hardware acceleration
        run: |
          test -r /dev/kvm && test -w /dev/kvm
          "$ANDROID_HOME/emulator/emulator" -accel-check
      - name: Run instrumented tests
        run: ./gradlew :app:pixel6DebugAndroidTest
```

Android Gradle Plugin’inizin gerektirdiği Java sürümünü kullanın ve test görevini projenizin yönetilen-cihaz göreviyle değiştirin. Bir **x86_64** sistem imajı yapılandırın. Hem Gradle hem de emülatörler için yeterli belleğe sahip bir çalıştırıcı şekli seçin; eşzamanlı cihazlar işin CPU ve bellek tahsisini paylaşır.

Emülatörü normal çalıştırıcı kullanıcısı olarak çalıştırın. Bu örnekte `sudo` yalnızca işletim sistemi paketlerini yüklemek içindir.

Emülatörler iç içe sanallaştırma kullandığından zamanlamaları fiziksel bir Android cihazdan farklı olabilir. Emülatör kıyaslamalarını o CI ortamının ölçümleri olarak değerlendirin, fiziksel cihaz performansı olarak değil.

## Eşzamanlılık sınırları {#concurrency-limits}

Her hesabın macOS ve Linux için bağımsız vCPU ve bellek eşzamanlılık sınırları vardır. Tuist bir işi kabul etmeden önce, işin <.localized_link href="/guides/features/runners/profiles#machine-shapes">makine şeklini</.localized_link> o platformda şu anda çalışan tüm işlerle karşılaştırır. İş yalnızca vCPU’su ve belleği kalan kapasiteye sığdığında başlar; aksi takdirde kapasite uygun hale gelene kadar kuyrukta kalır. Bir platformdaki iş asla diğer platformun kapasitesini tüketmez.

Air hesaplarının sabit eşzamanlılık sınırları vardır. Pro ve Enterprise hesapları altı standart macOS işi (48 vCPU / 144 GB) ve Linux’ta 64 vCPU / 128 GB ile başlar; Tuist, yinelenen kullanıma ve aktif çalıştırıcıların yanına sığmayan son kuyruktaki işlere dayanarak otomatik olarak ek boşluk ekler. Bir sınır düşükken (on iki standart macOS işine kadar veya Linux’ta 128 vCPU / 512 GB’a kadar), saatte bir kez olmak üzere tüm kuyruktaki işleri kapsayacak şekilde büyüyebilir. Bunun üzerinde, ani bir artışın sınırsız eşzamanlılık sağlamaması için bir güvenlik tavanına kadar günde en fazla bir kez ve her seferinde en fazla %50 oranında büyür. Otomatik ayarlamalar yalnızca sınırları artırır: mevcut tahsisler ve sözleşmeli minimum kapasite korunur. Daha yüksek bir hesap sınırı, makinelerin hemen kullanılabilir olacağını garanti etmez.

Çalıştırıcılar panosundaki **Eşzamanlılık** bölümü, her saat için kabul edilen en yüksek vCPU ve bellek kullanımını gösterir; her saatin başında bilinen sınır için basamaklı bir çizgi bulunur. Kırmızı çubuklar bu geçmiş eşiğe ulaşmıştır; bunlar tek başına bir işin beklediğini kanıtlamaz. Bir saat içindeki bir artış, zirveyi kova başlangıç çizgisinin üzerine çıkarabilir. Mevcut sınırlar her grafiğin yanında gösterilir. Geçmiş izlemenin başlamasından önceki dönemlerde varsayılan bir geçmiş değeri yerine sınır çizgisi bulunmaz.

İş akışları güvenlik tavanında kuyrukta kalmaya devam ederse, gerekli kapasiteyi inceleyebilmemiz için hesap kullanıcı adınızı, platformu ve beklenen paralel iş yükünüzü belirterek [bize ulaşın](mailto:contact@tuist.dev).

## Ağ erişimi {#network-access}

İşler genel internete giden bağlantılar açabilir. Özel adres aralıkları (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) engellenir ve çalıştırıcılar gelen bağlantıları kabul etmez.

| Platform | Giden portlar |
| --- | --- |
| Linux | TCP 22 (SSH), 80 (HTTP) ve 443 (HTTPS), artı DNS |
| macOS | Tüm portlar |

SSH, `git@` bağımlılıklarını, SSH alt modüllerini, dağıtım anahtarlarını ve `ssh` veya `scp` dağıtımlarını kapsar. Bir Linux iş akışı başka bir giden porta ihtiyaç duyuyorsa [bize ulaşın](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub’ı bağlayın, runs-on’ı bir Tuist profiline yönlendirin ve filodaki ilk işinizi çalıştırın."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Kümenizi bağlayın, bir kuyruğu bir Tuist profilinin adıyla adlandırın ve bir adımdan hedefleyin."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab’ı bir kez bağlayın ve her işin makinesini pipeline etiketleriyle seçin."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="Çalışma alanınızı bağlayın ve kendi kendine barındırılan çalıştırıcı havuzlarınızın derlemelerini Tuist profillerinde çalıştırın."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="Kendi git forgenizden veya orkestratörünüzden tek bir istekle işleri çalıştırın ve webhook’larla takip edin."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiller"
    details="İşlerinizden başvurduğunuz adlandırılmış makine profilleriyle bir platform, boyut ve Xcode sürümü seçin."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="İmajlar"
    details="macOS ve Linux çalıştırıcılarda önceden yüklü olanları görün: Xcode, simülatörler, Metal araç zinciri, Docker, Android SDK ve daha fazlası."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Önbellek birimleri"
    details="Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında koruyun; her çalıştırma için özel yazılabilir bir kopya sağlanır."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo grafik eylemleri {#struo-graph-actions}

<a id="once-graph-actions"></a>

Hesapta uzaktan yürütme etkinleştirildiğinde ve sunucu uyumlu çalıştırıcı yeteneklerini duyurduğunda, Struo uygun grafik komut eylemlerini Tuist'in Linux çalışanlarında yürütebilir. Bu, yukarıdaki CI sağlayıcı işlerinden ayrı olarak eylem düzeyinde bir yürütmedir. Kurulum, imaj gereksinimleri ve uyumluluk kontrolleri için <.localized_link href="/guides/features/runners/struo">Struo uzaktan yürütme</.localized_link> bölümüne bakın.

## Neden Tuist Çalıştırıcıları {#why-tuist-runners}

Çoğu CI çalıştırıcı sağlayıcısı, daha güçlü makineler ve kalıcı bir önbellek sunarak işleri hızlandırır; bu genellikle CI çalıştırmalarınıza yeniden monte edilen paylaşılan bir birimdir. Bu yardımcı olur ancak bir birim yalnızca bir diskten ibarettir: önceki CI çalıştırmalarının üzerinde bıraktığı her şeyi taşır. Yalnızca en güncel yapıtları derlemelerin çalıştığı yere yakın tutmak için çoğaltılmaz ve kodunuzun derlendiği diğer yerlere asla ulaşmaz.

Derleme artık tek bir yerde gerçekleşmiyor. Aynı kod, geliştirici dizüstü bilgisayarlarında, CI ortamlarında ve giderek artan şekilde kodlama ajanları ile diğer otomatik ortamlarda derleniyor. Tuist Çalıştırıcıları farklıdır çünkü kullandığınız derleme sisteminden bağımsız olarak, tüm bu ortamların zaten okuyup yazdığı aynı <.localized_link href="/guides/features/cache">önbelleği</.localized_link> paylaşırlar. Bir ekip arkadaşının dizüstü bilgisayarında ısıttığı, bir ajanın ürettiği veya önceki bir derlemenin geride bıraktığı yapıtlar çalıştırıcıda isabet oluşturur ve tam tersi de geçerlidir. Isıtılması gereken ayrı bir CI önbelleği yoktur ve hızlanma yalnızca CI ile sınırlı değildir.

Buna ek olarak, önbellek çalıştırıcıyla aynı özel ağ üzerinde birlikte konumlandırılır; böylece önbellek okuma ve yazma işlemleri genel interneti geçmek yerine dahili kalır ve hesaplama kaynağına yakın gerçekleşir.

Özetle:

- **Tüm ortamlarda paylaşılır.** Çalıştırıcı, geliştirici makineleriniz, CI ve kodlama ajanlarınızla aynı önbelleği okur ve yazar; bu sayede herhangi bir yerde yapılan iş her yerde önbelleği ısıtır.
- **Hesaplama kaynağıyla birlikte konumlandırılır.** Önbellek trafiği genel bir giriş noktası üzerinden değil, çalıştırıcının yanındaki dahili ağda kalır.
- **Tek bir sistem, sonradan eklenmiş değil.** Önbellekleme, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link>, <.localized_link href="/guides/features/test-sharding">test parçalama</.localized_link> ve <.localized_link href="/guides/features/build-insights">derleme içgörülerinin</.localized_link> tümü aynı proje ve hesap üzerinden çalışır; bu nedenle çalıştırıcı, derleme verileri için ayrı bir yalıtılmış alan değildir.
