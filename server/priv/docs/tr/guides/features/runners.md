---
{
  "title": "Çalıştırıcılar",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcıları, GitHub Actions, Buildkite, GitLab CI ve Bitrise için yönetilen macOS ve Linux çalıştırıcılardır; önbellek, hesaplama kaynaklarıyla aynı konumda bulunur ve yerel makinelerinizle paylaşılır."
}
---
# Runners {#runners}

Tuist Runners, GitHub Actions, Buildkite, GitLab CI ve Bitrise pipeline'larınız için yönetilen macOS ve Linux çalıştırıcılarıdır. İşleri CI sağlayıcınızın barındırdığı makinelerde çalıştırmak yerine, bir işi bir Tuist <.localized_link href="/guides/features/runners/profiles">profiline</.localized_link> yönlendirirsiniz ve iş, ekibinizin zaten kullandığı aynı <.localized_link href="/guides/features/cache">önbelleğin</.localized_link> yanında, Tuist'in filosunda çalışır; kurulması gereken bir çalıştırıcı aracı veya bakımı yapılması gereken bir altyapı yoktur. Makineleri değiştirmeden önce CI faturanızı neyin etkilediğini anlamak için [CI maliyetlerine](https://tuist.dev/solutions/ci-costs) bakın.

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

Çalıştırıcı imajı Android SDK'yı içerir. Bir cihazı başlatmadan önce öykünücüyü ve çalışma zamanı kitaplıklarını yükleyin. Zaten `pixel6` adında bir Gradle Yönetilen Cihaz tanımlayan bir proje için GitHub Actions işi şu şekilde görünür:

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

Öykünücüler iç içe sanallaştırma kullanır, bu nedenle zamanlamaları fiziksel bir Android cihazdan farklı olabilir. Öykünücü kıyaslamalarını fiziksel cihaz performansı yerine o CI ortamının ölçümleri olarak değerlendirin.

## Eşzamanlılık sınırları {#concurrency-limits}

Her hesabın macOS ve Linux için bağımsız vCPU ve bellek eşzamanlılık sınırları vardır. Tuist bir işi kabul etmeden önce, işin <.localized_link href="/guides/features/runners/profiles#machine-shapes">makine şeklini</.localized_link> o platformda şu anda çalışan tüm işlere göre kontrol eder. İş, yalnızca vCPU'su ve belleği kalan kapasiteye sığdığında başlar; aksi takdirde kapasite kullanılabilir hale gelene kadar kuyrukta kalır. Bir platformdaki işler asla diğer platformun kapasitesini tüketmez.

Air hesaplarının sabit eşzamanlılık sınırları vardır. Pro ve Enterprise hesapları için Tuist, yinelenen kullanıma ve aktif çalıştırıcıların yanına sığmayan son kuyruktaki işlere dayanarak otomatik olarak ek alan sağlar. Otomatik ayarlamalar yalnızca sınırları artırır: mevcut haklar ve sözleşmeli minimum kapasite korunur. Büyüme kademeli olup güvenlik tavanlarıyla sınırlıdır, bu nedenle ani bir artış sınırsız eşzamanlılık sağlamaz. Daha yüksek bir hesap limiti, makinelerin hemen kullanılabilir olacağını garanti etmez.

Runners panosundaki **Eşzamanlılık** bölümü, her saat için izin verilen en yüksek vCPU ve bellek kullanımını gösterir; her saatin başında bilinen limit için basamaklı bir çizgi bulunur. Kırmızı çubuklar o geçmiş eşiğe ulaşmıştır; bunlar tek başına bir işin beklediğini kanıtlamaz. Bir saat içindeki artış, zirveyi kova başlangıç çizgisinin üzerine çıkarabilir. Mevcut limitler her grafiğin yanında gösterilir. Geçmiş izleme başlamadan önceki dönemlerde varsayılan bir geçmiş değeri yerine limit çizgisi bulunmaz.

İş akışları güvenlik tavanında kuyrukta beklemeye devam ederse, gerekli kapasiteyi inceleyebilmemiz için hesap adınızı, platformu ve beklenen paralel iş yükünüzle birlikte [bize ulaşın](mailto:contact@tuist.dev).

## Ağ erişimi {#network-access}

İşler genel internete giden bağlantılar açabilir. Özel adres aralıkları (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) engellenmiştir ve çalıştırıcılar gelen bağlantıları kabul etmez.

| Platform | Giden portlar |
| --- | --- |
| Linux | TCP 22 (SSH), 80 (HTTP) ve 443 (HTTPS), ayrıca DNS |
| macOS | Tüm portlar |

SSH, `git@` bağımlılıklarını, SSH alt modüllerini, dağıtım anahtarlarını ve `ssh` veya `scp` dağıtımlarını kapsar. Bir Linux iş akışı başka bir giden porta ihtiyaç duyuyorsa [bize ulaşın](mailto:contact@tuist.dev).

<.home_cards>
  <.home_card
    title="GitHub Actions"
    details="GitHub'ı bağlayın, runs-on değerini bir Tuist profiline yönlendirin ve filodaki ilk işinizi çalıştırın."
    link="/guides/features/runners/ci-providers/github-actions"
/>
  <.home_card
    title="Buildkite"
    details="Kümenizi bağlayın, bir kuyruğu bir Tuist profiliyle adlandırın ve bir adımdan onu hedefleyin."
    link="/guides/features/runners/ci-providers/buildkite"
/>
  <.home_card
    title="GitLab CI"
    details="GitLab'ı bir kez bağlayın ve her işin makinesini pipeline etiketleriyle seçin."
    link="/guides/features/runners/ci-providers/gitlab-ci"
/>
  <.home_card
    title="Bitrise"
    details="Çalışma alanınızı bağlayın ve kendi barındırdığınız çalıştırıcı havuzlarınızın derlemelerini Tuist profillerinde çalıştırın."
    link="/guides/features/runners/ci-providers/bitrise"
/>
  <.home_card
    title="API"
    details="İşleri kendi git forgenizden veya orkestratörünüzden tek bir istekle çalıştırın ve webhook'larla takip edin."
    link="/guides/features/runners/ci-providers/api"
/>
  <.home_card
    title="Profiller"
    details="İşlerinizden referans verdiğiniz adlandırılmış makine profilleriyle bir platform, boyut ve Xcode sürümü seçin."
    link="/guides/features/runners/profiles"
/>
  <.home_card
    title="İmajlar"
    details="macOS ve Linux çalıştırıcılarında önceden yüklü olanları görün: Xcode, simülatörler, Metal araç zinciri, Docker, Android SDK ve daha fazlası."
    link="/guides/features/runners/images"
/>
  <.home_card
    title="Önbellek birimleri"
    details="Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri işler arasında koruyun; her çalıştırma için özel yazılabilir bir kopya ile."
    link="/guides/features/runners/cache-volumes"
/>
</.home_cards>

## Struo graf eylemleri {#struo-graph-actions}

<a id="once-graph-actions"></a>

Hesapta uzaktan yürütme etkinleştirildiğinde ve sunucu uyumlu çalıştırıcı yeteneklerini duyurduğunda Struo, uygun graf komut eylemlerini Tuist'in Linux çalışanlarında yürütebilir. Bu, yukarıdaki CI sağlayıcı işlerinden ayrı olarak eylem düzeyinde bir yürütmedir. Kurulum, imaj gereksinimleri ve uyumluluk kontrolleri için <.localized_link href="/guides/features/runners/struo">Struo uzaktan yürütme</.localized_link> bölümüne bakın.

## Neden Tuist Çalıştırıcıları {#why-tuist-runners}

Çoğu CI çalıştırıcı sağlayıcısı, daha güçlü makineler ve kalıcı bir önbellek (genellikle CI çalıştırmalarınıza yeniden monte edilen paylaşılan bir birim) sunarak işleri hızlandırır. Bu yardımcı olur ancak bir birim yalnızca bir diskten ibarettir: önceki CI çalıştırmalarının üzerinde bıraktığı her şeyi taşır. Yalnızca en güncel yapıtları derlemelerin çalıştığı yere yakın tutmak için çoğaltılmaz ve kodunuzun derlendiği diğer yerlere asla ulaşmaz.

Derleme artık tek bir yerde gerçekleşmiyor. Aynı kod, geliştirici dizüstü bilgisayarlarında, CI ortamlarında ve giderek artan şekilde kodlama ajanları ile diğer otomatik ortamlarda derleniyor. Tuist Çalıştırıcıları farklıdır çünkü kullandığınız derleme sisteminden bağımsız olarak, tüm bu ortamların zaten okuyup yazdığı aynı <.localized_link href="/guides/features/cache">önbelleği</.localized_link> paylaşırlar. Bir ekip arkadaşının dizüstü bilgisayarında ısıttığı, bir ajanın ürettiği veya önceki bir derlemenin geride bıraktığı yapıtlar çalıştırıcıda isabet olarak kaydedilir ve tersi de geçerlidir. Isıtılması gereken ayrı bir CI önbelleği yoktur ve hızlanma yalnızca CI ile sınırlı değildir.

Buna ek olarak, önbellek çalıştırıcıyla aynı özel ağ üzerinde birlikte konumlandırılır; böylece önbellek okuma ve yazma işlemleri genel interneti geçmek yerine dahili kalır ve hesaplama kaynaklarına yakın gerçekleşir.

Özetle:

- **Her ortamda paylaşılır.** Çalıştırıcı, geliştirici makineleriniz, CI ve kodlama ajanlarınızla aynı önbelleği okur ve yazar; bu sayede herhangi bir yerde yapılan iş, önbelleği her yerde ısıtır.
- **Hesaplama kaynaklarıyla birlikte konumlandırılır.** Önbellek trafiği, genel bir giriş noktası üzerinden değil, çalıştırıcının yanındaki dahili ağda kalır.
- **Tek bir sistem, sonradan eklenmiş değil.** Önbellekleme, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link>, <.localized_link href="/guides/features/test-sharding">test parçalama</.localized_link> ve <.localized_link href="/guides/features/build-insights">derleme içgörülerinin</.localized_link> tümü aynı proje ve hesap üzerinde çalışır; böylece çalıştırıcı, derleme verilerinin ayrı bir yalıtılmış bölümü haline gelmez.
