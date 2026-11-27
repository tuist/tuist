---
{
  "title": "Çalıştırıcılar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcıları; GitHub Actions, Buildkite, GitLab CI ve Bitrise için yönetilen macOS ve Linux çalıştırıcılarıdır. Önbellek, hesaplama kaynağının yanında konumlandırılır ve yerel makinelerinizle paylaşılır."
}
---
# Çalıştırıcılar {#runners}

Tuist Çalıştırıcıları, GitHub Actions, Buildkite, GitLab CI ve Bitrise işlem hatlarınız için yönetilen macOS ve Linux çalıştırıcılardır. İşleri CI sağlayıcınızın barındırdığı makinelerde çalıştırmak yerine, bir işi bir Tuist <.localized_link href="/guides/features/runners/profiles">profiline</.localized_link> yönlendirirsiniz; iş, ekibinizin zaten kullandığı aynı <.localized_link href="/guides/features/cache">önbelleğin</.localized_link> yanında, Tuist’in filolarında çalışır. Kurulması gereken bir çalıştırıcı aracısı veya bakımını yapmanız gereken bir altyapı yoktur. Makineleri değiştirmeden önce CI faturanızı neyin etkilediğini anlamak için [CI maliyetlerine](https://tuist.dev/solutions/ci-costs) bakın.

Bunları benimsemek genellikle bir işte tek satırlık bir değişikliktir:

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

## Linux üzerinde Android öykünücüleri {#android-emulators}

Linux çalıştırıcıları varsayılan olarak `/dev/kvm` üzerinden donanım hızlandırmalı sanallaştırma sağlar. Gradle Yönetilen Cihazlar dahil olmak üzere x86_64 Android öykünücülerini çalıştırmak için olağan Linux <.localized_link href="/guides/features/runners/profiles">profilinizi</.localized_link>, örneğin `tuist-linux`, kullanın. Cihaza erişmek için özel bir çalıştırıcı profili, KVM kurulum eylemi, izin değişikliği veya `sudo` gerekmez.

Çalıştırıcı imajı Android SDK’yı içerir. Bir cihazı başlatmadan önce öykünücüyü ve çalışma zamanı kütüphanelerini yükleyin. Zaten `pixel6` adlı bir Gradle Yönetilen Cihaz tanımlayan bir proje için GitHub Actions işi şu şekilde görünür:

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

Android Gradle Eklentinizin gerektirdiği Java sürümünü kullanın ve test görevini projenizin yönetilen-cihaz göreviyle değiştirin. Bir **x86_64** sistem imajı yapılandırın. Hem Gradle hem de öykünücüler için yeterli belleğe sahip bir çalıştırıcı şekli seçin; eşzamanlı cihazlar işin CPU ve bellek tahsisini paylaşır.

Öykünücüyü normal çalıştırıcı kullanıcısı olarak çalıştırın. Bu örnekte `sudo` yalnızca işletim sistemi paketlerini yüklemek içindir.

Öykünücüler iç içe sanallaştırma kullandığından zamanlamaları fiziksel bir Android cihazdan farklı olabilir. Öykünücü kıyaslamalarını fiziksel cihaz performansı yerine o CI ortamının ölçümleri olarak değerlendirin.

## Eşzamanlılık sınırları {#concurrency-limits}

Her hesabın macOS ve Linux için bağımsız vCPU ve bellek eşzamanlılık sınırları vardır. Tuist bir işi kabul etmeden önce, işin <.localized_link href="/guides/features/runners/profiles#machine-shapes">makine şeklini</.localized_link> o platformda şu anda çalışan tüm işlere göre kontrol eder. İş, vCPU’su ve belleği kalan kapasiteye sığdığında başlar; aksi takdirde kapasite uygun olana kadar kuyrukta kalır. Bir platformdaki işler asla diğer platformun kapasitesini tüketmez.

Air hesaplarının sabit eşzamanlılık sınırları vardır: iki standart macOS işi (16 vCPU / 48 GB) ve Linux’ta 16 vCPU / 64 GB. Pro ve Enterprise hesapları altı standart macOS işi (48 vCPU / 144 GB) ve Linux’ta 64 vCPU / 128 GB ile başlar; Tuist, yinelenen kullanıma ve aktif çalıştırıcıların yanına sığmayan son kuyruk işlerine dayanarak otomatik olarak ek alan sağlar. Bir sınır düşükken (on iki standart macOS işine veya Linux’ta 128 vCPU / 512 GB’a kadar), saatte bir kez kadar sıklıkla tüm kuyruk işlerini karşılayacak şekilde büyüyebilir. Bunun üzerinde, günlük en fazla bir kez ve her seferinde en fazla %50 oranında, bir güvenlik tavanına kadar büyür; böylece ani bir artış sınırsız eşzamanlılık sağlamaz. Otomatik ayarlamalar yalnızca sınırları artırır: mevcut tahsisler ve sözleşmeli asgari kapasite korunur. Daha yüksek bir hesap limiti, makinelerin hemen kullanılabilir olduğunu garanti etmez.

Çalıştırıcılar panosundaki **Eşzamanlılık** bölümü, her saat için kabul edilen en yüksek vCPU ve bellek kullanımını gösterir; her saatin başında bilinen limit için basamaklı bir çizgi bulunur. Kırmızı çubuklar o geçmiş eşiğe ulaşmıştır; bunlar tek başına bir işin beklediğini kanıtlamaz. Bir saat içindeki artış, zirveyi kova başlangıç çizgisinin üzerine çıkarabilir. Mevcut limitler her grafiğin yanında gösterilir. Geçmiş izlemenin başladığı dönemlerden önceki dönemlerde varsayılan bir geçmiş değeri yerine limit çizgisi bulunmaz.

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
    details="GitHub’ı bağlayın, runs-on değerini bir Tuist profiline yönlendirin ve ilk işinizi filoda çalıştırın."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Kümenizi bağlayın, bir kuyruğu bir Tuist profiliyle adlandırın ve bir adımdan bu kuyruğu hedefleyin."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab’ı bir kez bağlayın ve her işin makinesini işlem hattı etiketleriyle seçin."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="Çalışma alanınızı bağlayın ve kendi kendine barındırılan çalıştırıcı havuzlarınızın derlemelerini Tuist profillerinde çalıştırın."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="Kendi git forjunuzdan veya orkestratörünüzden tek bir istekle işleri çalıştırın ve webhook’larla takip edin."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiller"
    details="İşlerinizden başvurduğunuz adlandırılmış makine profilleriyle bir platform, boyut ve Xcode sürümü seçin."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="İmajlar"
    details="macOS ve Linux çalıştırıcılarında önceden yüklü olanları görün: Xcode, simülatörler, Metal araç zinciri, Docker, Android SDK ve daha fazlası."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Önbellek birimleri"
    details="Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında koruyun; her çalıştırma için özel, yazılabilir bir kopya sağlanır."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo grafik eylemleri {#struo-graph-actions}

<a id="once-graph-actions"></a>

Hesapta uzaktan yürütme etkinleştirildiğinde ve sunucu uyumlu çalıştırıcı yeteneklerini duyurduğunda Struo, uygun grafik komut eylemlerini Tuist'in Linux çalışanlarında yürütebilir. Bu, yukarıdaki CI sağlayıcı işlerinden ayrı olarak eylem düzeyinde bir yürütmedir. Kurulum, imaj gereksinimleri ve uyumluluk kontrolleri için <.localized_link href="/guides/features/runners/struo">Struo uzaktan yürütme</.localized_link> bölümüne bakın.

## Neden Tuist Runners {#why-tuist-runners}

Çoğu CI çalıştırıcı sağlayıcısı, size daha güçlü makineler ve kalıcı bir önbellek (genellikle CI çalıştırmalarınıza yeniden monte edilen paylaşılan bir birim) sunarak işleri hızlandırır. Bu yardımcı olur ancak bir birim yalnızca bir diskten ibarettir: önceki CI çalıştırmalarının üzerinde bıraktığı her şeyi taşır. Yalnızca en güncel yapıtları derlemelerin çalıştığı yere yakın tutmak için çoğaltılmaz ve kodunuzun derlendiği diğer yerlere asla ulaşmaz.

Derleme artık tek bir yerde gerçekleşmiyor. Aynı kod, geliştirici dizüstü bilgisayarlarında, CI ortamında ve giderek artan şekilde kodlama ajanları ile diğer otomatik ortamlarda derleniyor. Tuist Runners farklıdır çünkü kullandığınız derleme sistemi ne olursa olsun, tüm bu ortamların zaten okuyup yazdığı aynı <.localized_link href="/guides/features/cache">önbelleği</.localized_link> paylaşır. Bir ekip arkadaşının dizüstü bilgisayarında önceden ısıttığı, bir ajanın ürettiği veya önceki bir derlemenin geride bıraktığı yapıtlar çalıştırıcıda isabet oluşturur ve tam tersi de geçerlidir. Isıtılması gereken ayrı bir CI önbelleği yoktur ve hızlanma yalnızca CI ile sınırlı değildir.

Buna ek olarak, önbellek aynı özel ağ üzerinde çalıştırıcıyla birlikte konumlandırılır; böylece önbellek okuma ve yazma işlemleri genel internet üzerinden geçmek yerine dahili kalır ve hesaplama kaynağına yakın gerçekleşir.

Bir araya getirildiğinde:

- **Tüm ortamlarda paylaşılır.** Çalıştırıcı, geliştirici makineleriniz, CI ve kodlama ajanlarınızla aynı önbelleği okur ve yazar; böylece herhangi bir yerde yapılan iş, önbelleği her yerde ısıtır.
- **Hesaplama kaynağıyla birlikte konumlandırılır.** Önbellek trafiği, genel bir giriş noktası üzerinden değil, çalıştırıcının yanındaki dahili ağda kalır.
- **Ayrı bir sistem değil, bütünleşik.** Önbellekleme, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link>, <.localized_link href="/guides/features/test-sharding">test parçalama</.localized_link> ve <.localized_link href="/guides/features/build-insights">derleme içgörülerinin</.localized_link> tümü aynı proje ve hesap üzerinden çalışır; böylece çalıştırıcı, derleme verilerinin ayrı bir yalıtılmış bölümü haline gelmez.
