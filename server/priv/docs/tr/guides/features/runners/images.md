---
{
  "title": "Görüntüler",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcılarında önceden yüklü olanlar: Xcode, simülatörler ve Metal araç zinciri içeren macOS görüntüleri ile Docker ve Android SDK içeren Ubuntu görüntüleri."
}
---
# Görseller {#images}

Her Tuist Runners işi, bir runner görselinden başlatılan temiz bir sanal makinede çalışır. <.localized_link href="/guides/features/runners/profiles">Profiliniz</.localized_link> görseli seçer: platformu, macOS’taki Xcode sürümünü ve Linux’taki Ubuntu dağıtımını. İş bittiğinde sanal makine atılır; bu nedenle bir işin kurduğu her şey sonraki iş için silinir.

Görseller, iş akışları için önemli olan noktalarda GitHub tarafından barındırılan runner’ları takip eder: aynı kullanıcı, ev dizini ve çalışma alanı yolları, `ImageOS`, şifresiz `sudo` ve çoğu iOS, macOS ile Linux iş akışının beklediği araçlar. GitHub’ınkilerden bilinçli olarak daha küçüktürler; bu nedenle farklılıklar aşağıda her platform için listelenmiştir.

## Görsel seçimi {#choosing-an-image}

- **Xcode, Apple SDK’ları veya simülatörler:** projenizin derlendiği Xcode sürümüne sabitlenmiş bir macOS profili.
- **Docker, Android derlemeleri ve öykünücüler veya diğer Linux araçları:** Ubuntu 24.04 üzerinde bir Linux profili.
- **Ubuntu 24.04’ü henüz desteklemeyen bir bağımlılık:** Ubuntu 22.04 üzerinde bir Linux profili.

macOS’ta görseli değil, Xcode’u seçersiniz: her Xcode sürümü kendi görseline sahiptir ve `26.4.1` sürümüne sabitlenmiş bir profil her zaman Xcode 26.4.1 ile oluşturulmuş görselde çalışır. İki Xcode sürümünü çalıştırmak için her biri için bir profil oluşturun.

## macOS {#macos}

macOS runner’ları, **macOS 26 Tahoe** çalıştıran Apple silicon (arm64) sanal makinelerdir. Bir runner’ın adı tam macOS sürümünü içerir; örneğin `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…` ve işin **İşi ayarla** adımında görünür.

### Xcode {#xcode}

Her görsel **tam olarak bir Xcode** içerir; bu, `xcode-select` ile seçilir, böylece `xcodebuild` ve `xcrun` ek bir kurulum adımı olmadan onu kullanır. Bu, GitHub tarafından barındırılan görsellerden temel farktır; onlar iş zamanında geçiş yapmak için birkaç Xcode sürümüyle gelir. Mevcut sürümler:

{{runner_macos_xcode_versions}}

- **Yol.** Xcode `/Applications/Xcode_<version>.app` konumundadır. Yama bileşeni içeren bir sürüm için `/Applications/Xcode_<major>.<minor>.app` aynı paketi işaret eder, dolayısıyla `Xcode_26.4.app` değeri `Xcode_26.4.1.app` olarak çözümlenir. GitHub tarzı bir yolu sabit kodlayan veya bunu `xcode-select -s` çağrısında kullanan iş akışları çalışmaya devam eder.
- **Simülatörler.** O Xcode ile birlikte gelen iOS, tvOS, watchOS ve visionOS simülatör çalışma zamanları görselin içine indirilir; böylece ilk `xcodebuild test` çağrısı bunları almak zorunda kalmaz.
- **Metal araç zinciri.** Xcode 26’dan beri Metal derleyicisi Xcode ile birlikte gelmez ve ayrı olarak indirilmesi gerekir. Her görsel, kendi Xcode’una uygun Metal araç zincirini içerir ve işlerin çalıştığı kullanıcı için kuruludur; bu sayede `xcrun metal` ve `.metal` kaynaklarına sahip projeler, `xcodebuild -downloadComponent MetalToolchain` komutunu çalıştırmadan derlenir.
- **Beta sürümleri.** Beta profilleri (örneğin `27.3-beta`) o sürümün en son beta’sını takip eder. Apple yeni bir beta yayınladığında görsel yeniden oluşturulur ve profil tarafınızda herhangi bir değişiklik yapmadan buna geçer.

### Önceden yüklü yazılımlar {#macos-software}

- **Apple araçları:** Xcode (görsel başına bir adet), simülatör çalışma zamanları, Metal araç zinciri, `xcodes`, `xcbeautify`
- **Swift ve iOS araçları:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Cihazlar:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Diller ve çalışma zamanları:** `rbenv` aracılığıyla Ruby (2.7 ve en son iki 3.x sürümü, en yenisi varsayılan) Bundler ile, Node.js 24 npm, Yarn ve pnpm ile, Go, Java 21 (Temurin, `JAVA_HOME` olarak ayarlanır)
- **Paket ve sürüm yöneticileri:** Homebrew, mise
- **Sürüm kontrolü:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Yardımcı programlar:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI ajanları:** GitHub Actions runner, Buildkite agent, Bitrise agent ve CLI, GitLab job executor
- **Diğer:** Rosetta 2, `safaridriver` etkin

Araç sürümleri görsel oluşturulurken Homebrew’dan gelir ve görseller düzenli olarak yeniden oluşturulur. Bir runner’daki tam sürümü görmek için bir adımda yazdırın; örneğin `swiftlint version` veya `xcodebuild -version`.

### Ortam {#macos-environment}

- **Kullanıcı ve yollar.** İşler `runner` kullanıcısı olarak, ev dizini `/Users/runner` ve çalışma alanı `/Users/runner/work` ile çalışır; GitHub tarafından barındırılan runner’larla aynı yollardır, bu nedenle bu yolları sabit kodlayan eylemler çalışır.
- **`sudo`.** Şifresiz. Sanal makine yalnızca işinize aittir.
- **Homebrew.** Önek (`/opt/homebrew`) `runner` kullanıcısına aittir, bu nedenle `brew install <formula>` komutu `sudo` gerektirmeden çalışır. `HOMEBREW_NO_AUTO_UPDATE` ayarlanmıştır.
- **Kabuk.** Adımlar bir oturum açma kabuğunda çalışır, bu nedenle Homebrew, `rbenv` ve Node.js `PATH` yolundadır. `LANG` değeri `en_US.UTF-8` şeklindedir.
- **`ImageOS`** değeri `macos26` şeklindedir; GitHub tarafından barındırılan runner’larda olduğu gibi, buna göre önceden derlenmiş ikilileri seçen kurulum eylemleri için kullanılır.
- **Sertifikalar.** Apple’ın WWDR (G3) ve Developer ID (G2) ara sertifikaları, imzalama ve not onayı için sistem güven deposunda bulunur.
- **Gizlilik izinleri.** GitHub tarafından barındırılan görsellerde olduğu gibi, iki macOS gizlilik onayı önceden verilir: `create-dmg` ve `osascript` ihtiyaç duyduğu Apple Events üzerinden Finder betiklemesi ve UI testlerinde ses kaydeden uygulamaların ihtiyaç duyduğu iOS Simülatörü’nün mikrofona erişimi. Simülatör içindeki izinler, örneğin `simctl privacy`, işinizin sorumluluğunda kalır.
- **Disk.** Her iş en az 100 GB boş disk alanıyla başlar.

### Dahil değil {#macos-not-included}

- **Tuist CLI.** Sürümü projenizin kontrol etmesi için onu iş sırasında kurun; örneğin mise ile.
- **Diğer Xcode sürümleri.** `xcode-select` yerine Xcode sürümü başına bir profil kullanın.
- **Docker.** macOS runner’larında Docker daemon yoktur. Bir Linux profili kullanın; bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **GitHub’ın macOS’ta paketlediği araç zincirleri**, iOS derlemelerinin nadiren ihtiyaç duyduğu diğer Java sürümleri, Android SDK, .NET, Rust, Python sürümleri veya tarayıcılar gibi. Bunları bir adımda Homebrew, mise veya bir kurulum eylemi ile kurun.

## Linux {#linux}

Linux runner’lar, profil tarafından seçilen **Ubuntu 24.04** veya **Ubuntu 22.04** üzerinde çalışan x86_64 (amd64) sanal makinelerdir. Bir sürümün nasıl seçileceğini öğrenmek için bkz. <.localized_link href="/guides/features/runners/profiles#linux">Profiller</.localized_link>.

### Önceden yüklenmiş yazılımlar {#linux-software}

- **Derleme araç zinciri:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Geliştirme başlıkları:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** `pip` ve `venv` ile Python 3 (Ubuntu sürümünün versiyonu)
- **Konteynerler:** Buildx ve Compose ile Docker CLI; daemon işle birlikte çalışır (bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** `/usr/local/lib/android/sdk` konumunda Android SDK; komut satırı araçları, platform araçları ve API 34 ve üzeri her platform ve derleme araçları sürümü dahil, lisanslar kabul edilmiş durumda
- **Sürüm kontrolü:** Git, Git LFS, OpenSSH istemcisi, GitHub CLI (`gh`)
- **Veritabanı istemcileri:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Arşivler:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Yardımcı programlar:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI ajanları:** GitHub Actions runner, Buildkite agent, Bitrise agent ve CLI, GitLab job executor

### Ortam {#linux-environment}

- **Kullanıcı ve yollar.** İşler `runner` (UID 1000) kullanıcısı olarak, ev dizini `/home/runner` ile, `docker` grubunda ve şifresiz `sudo` ile çalışır.
- **`ImageOS`** değeri `ubuntu24` veya `ubuntu22` şeklindedir; GitHub tarafından barındırılan runner’larla eşleşir.
- **Android.** `ANDROID_HOME` ve `ANDROID_SDK_ROOT` SDK’yı işaret eder. Emülatör önceden yüklenmemiştir; bkz. <.localized_link href="/guides/features/runners#android-emulators">Android emülatörleri</.localized_link>.
- **Yerel ayar.** `LANG` ve `LC_ALL` değerleri `C.UTF-8` şeklindedir ve `DEBIAN_FRONTEND` değeri `noninteractive` şeklindedir, bu nedenle `sudo apt-get install` istemde bulunmaz.

### Dahil değil {#linux-not-included}

Linux görseli, GitHub’ın önceden yüklediği her dil araç zinciri yerine temel derleme gereksinimlerini karşılar. İşinizin ihtiyaç duyduklarını olağan kurulum eylemleri (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise veya `apt-get` ile kurun:

- **Dil çalışma zamanları**; Java, Node.js, Go, Ruby, .NET ve Rust gibi.
- **Android NDK.** İhtiyacınız olan sürümü `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` ile kurun. `ANDROID_NDK_HOME` ayarlanmamış bırakılır, böylece olmayan bir NDK’yı işaret etmek yerine derleme açıkça başarısız olur.
- **Tarayıcılar** ve `kubectl`, Helm ile `gh` dışındaki bulut CLI’ları.

Bir araç zincirini her seferinde kurmak yerine işler arasında korumak için onu bir <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimine</.localized_link> yerleştirin.

## Görsel güncellemeleri {#image-updates}

Görseller, Apple yeni bir Xcode veya beta yayınladığında, CI ajanları güncellendiğinde ve görsellerin kendilerini değiştirdiğimizde yeniden oluşturulur. Bir iş her zaman tam ve test edilmiş bir görsel üzerinde çalışır: yeni görseler filoya kademeli olarak dağıtılır ve bir iş çalışırken asla değişmez.

İş akışınızın güvendiği bir araç eksikse, [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack’inde](https://slack.tuist.dev) sorun.
