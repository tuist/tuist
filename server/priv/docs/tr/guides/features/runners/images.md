---
{
  "title": "İmajlar",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcılarda önceden yüklü olanlar: Xcode, simülatörler ve Metal araç zinciri içeren macOS imajları ile Docker ve Android SDK içeren Ubuntu imajları."
}
---
# Görüntüler {#images}

Her Tuist Runners işi, bir runner görüntüsünden başlatılan temiz bir sanal makinede çalışır. <.localized_link href="/guides/features/runners/profiles">Profiliniz</.localized_link> görüntüyü seçer: platformu, macOS üzerindeki Xcode sürümünü ve Linux üzerindeki Ubuntu sürümünü. İş bittiğinde VM atılır, bu nedenle bir işin kurduğu her şey sonraki iş için kaybolur.

Görüntüler, iş akışları için önemli olan noktalarda GitHub tarafından barındırılan runner'ları takip eder: aynı kullanıcı, ev dizini ve çalışma alanı yolları, `ImageOS`, şifresiz `sudo` ve çoğu iOS, macOS ve Linux iş akışının beklediği araçlar. Kasıtlı olarak GitHub'ınkinden daha küçüktürler, bu nedenle farklılıklar her platform için aşağıda listelenmiştir.

## Bir görüntü seçme {#choosing-an-image}

- **Xcode, Apple SDK'ları veya simülatörler:** Projenizin derlendiği Xcode sürümüne sabitlenmiş bir macOS profili.
- **Docker, Android derlemeleri ve emülatörler veya diğer Linux araçları:** Ubuntu 24.04 üzerinde bir Linux profili.
- **Henüz Ubuntu 24.04'ü desteklemeyen bir bağımlılık:** Ubuntu 22.04 üzerinde bir Linux profili.

macOS'ta görüntüyü değil, Xcode'u seçersiniz: her Xcode sürümü kendi görüntüsüdür ve `26.4.1` sürümüne sabitlenmiş bir profil her zaman Xcode 26.4.1 ile oluşturulan görüntüde çalışır. İki Xcode sürümünü çalıştırmak için her biri için bir profil oluşturun.

## macOS {#macos}

macOS runner'ları, **macOS 26 Tahoe** çalıştıran Apple silicon (arm64) sanal makinelerdir. Bir runner'ın adı tam macOS sürümünü içerir, örneğin `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…` ve işin **İşi Ayarla** adımında görünür.

### Xcode {#xcode}

Her görüntü **tam olarak bir Xcode** içerir; bu, `xcode-select` ile seçilir, böylece `xcodebuild` ve `xcrun` bunu bir kurulum adımı olmadan kullanır. Bu, iş zamanında geçiş yapmak için birkaç Xcode sürümü sunan GitHub tarafından barındırılan görüntülerden temel farktır. Mevcut sürümler:

{{runner_macos_xcode_versions}}

- **Yol.** Xcode `/Applications/Xcode_<version>.app` konumundadır. Yama bileşeni içeren bir sürüm için `/Applications/Xcode_<major>.<minor>.app` aynı paketi gösterir, bu nedenle `Xcode_26.4.app` değeri `Xcode_26.4.1.app` olarak çözülür. GitHub tarzı bir yolu sabit kodlayan veya bununla `xcode-select -s` çağıran iş akışları çalışmaya devam eder.
- **Simülatörler.** Bu Xcode ile birlikte gelen iOS, tvOS, watchOS ve visionOS simülatör çalışma zamanları görüntüye indirilir, böylece ilk `xcodebuild test` bunları almak zorunda kalmaz.
- **Metal araç zinciri.** Xcode 26'dan beri Metal derleyicisi Xcode ile birlikte gelmez ve ayrı olarak indirilmesi gerekir. Her görüntü, Xcode'u ile eşleşen Metal araç zincirini içerir; işlerin çalıştığı kullanıcı için kurulur, böylece `xcrun metal` ve `.metal` kaynaklarına sahip projeler `xcodebuild -downloadComponent MetalToolchain` çalıştırmadan derlenir.
- **Beta sürümleri.** Beta profilleri (örneğin `27.3-beta`) o sürümün en son betasını takip eder. Apple yeni bir beta yayınladığında, görüntü yeniden oluşturulur ve profil sizin tarafınızdan herhangi bir değişiklik yapılmadan buna geçer.

### Önceden yüklenmiş yazılımlar {#macos-software}

- **Apple araçları:** Xcode (görüntü başına bir tane), simülatör çalışma zamanları, Metal araç zinciri, `xcodes`, `xcbeautify`
- **Swift ve iOS araçları:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Cihazlar:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Diller ve çalışma zamanları:** Bundler ile `rbenv` aracılığıyla Ruby (2.7 ve en son iki 3.x sürümü, en yenisi varsayılan olarak), npm, Yarn ve pnpm ile Node.js 24
- **Paket ve sürüm yöneticileri:** Homebrew, mise
- **Sürüm kontrolü:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Yardımcı programlar:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI ajanları:** GitHub Actions runner, Buildkite ajanı, Bitrise ajanı ve CLI, GitLab iş yürütücüsü
- **Diğer:** Rosetta 2, `safaridriver` etkin

Araç sürümleri, görüntü oluşturulurken Homebrew'den gelir ve görüntüler düzenli olarak yeniden oluşturulur. Bir runner üzerindeki tam sürümü görmek için bunu bir adımda yazdırın, örneğin `swiftlint version` veya `xcodebuild -version`.

### Ortam {#macos-environment}

- **Kullanıcı ve yollar.** İşler `runner` olarak çalışır; ev dizini `/Users/runner` ve çalışma alanı `/Users/runner/work` olup, GitHub tarafından barındırılan runner'larla aynı yollardır, bu nedenle bunları sabit kodlayan eylemler çalışır.
- **`sudo`.** Şifresiz. VM yalnızca işinize aittir.
- **Homebrew.** Önek (`/opt/homebrew`) `runner` tarafından sahiplenilir, bu nedenle `brew install <formula>` `sudo` olmadan çalışır. `HOMEBREW_NO_AUTO_UPDATE` ayarlanmıştır.
- **Kabuk.** Adımlar bir oturum açma kabuğunda çalışır, bu nedenle Homebrew, `rbenv` ve Node.js `PATH` yolundadır. `LANG` değeri `en_US.UTF-8` şeklindedir.
- **`ImageOS`** değeri, GitHub tarafından barındırılan runner'larda olduğu gibi `macos26` şeklindedir; bu, önceden oluşturulmuş ikili dosyaları buna göre seçen kurulum eylemleri içindir.
- **Sertifikalar.** Apple'ın WWDR (G3) ve Developer ID (G2) ara sertifikaları, imzalama ve notasyon için sistem güven deposundadır.
- **Gizlilik izinleri.** GitHub tarafından barındırılan görüntülerde olduğu gibi, iki macOS gizlilik onayı önceden verilir: `create-dmg` ve `osascript` ihtiyaç duyduğu Apple Events aracılığıyla Finder betiği çalıştırma ve UI testlerinde ses kaydeden uygulamaların ihtiyaç duyduğu iOS Simülatörü'nün mikrofona erişimi. Bir simülatör içindeki izinler, örneğin `simctl privacy`, işinizin sorumluluğunda kalır.
- **Disk.** Her iş en az 100 GB boş disk alanıyla başlar.

### Dahil değil {#macos-not-included}

- **Tuist CLI.** Sürümü projenizin kontrol etmesi için bunu işte kurun, örneğin mise ile.
- **Diğer Xcode sürümleri.** `xcode-select` yerine Xcode sürümü başına bir profil kullanın.
- **Docker.** macOS runner'larında Docker daemon yoktur. Bir Linux profili kullanın; bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **GitHub'ın macOS'ta paketlediği araç zincirleri**, iOS derlemelerinin nadiren ihtiyaç duyduğu Java, Android SDK, .NET, Rust, Python sürümleri veya tarayıcılar gibi öğeleri içerir. Bunları bir adımda Homebrew, mise veya bir kurulum eylemi ile kurun.

## Linux {#linux}

Linux runner'lar, profil tarafından seçilen **Ubuntu 24.04** veya **Ubuntu 22.04** üzerinde çalışan x86_64 (amd64) sanal makinelerdir. Bir sürümün nasıl seçileceğini öğrenmek için bkz. <.localized_link href="/guides/features/runners/profiles#linux">Profiller</.localized_link>.

### Önceden yüklenmiş yazılımlar {#linux-software}

- **Derleme araç zinciri:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Geliştirme başlık dosyaları:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3, `pip` ve `venv` ile (Ubuntu sürümünün sürümü)
- **Konteynerler:** Buildx ve Compose içeren Docker CLI; daemon işle birlikte çalışır (bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Komut satırı araçları, platform araçları ve API 34 ve üzeri tüm platform ve derleme araçları sürümleriyle birlikte Android SDK `/usr/local/lib/android/sdk` konumunda bulunur; lisanslar kabul edilmiştir.
- **Sürüm kontrolü:** Git, Git LFS, OpenSSH istemcisi, GitHub CLI (`gh`)
- **Veritabanı istemcileri:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Arşivler:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Yardımcı programlar:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI ajanları:** GitHub Actions runner, Buildkite ajanı, Bitrise ajanı ve CLI, GitLab iş yürütücüsü

### Ortam {#linux-environment}

- **Kullanıcı ve yollar.** İşler `runner` (UID 1000) olarak çalışır; ev dizini `/home/runner` olup, `docker` grubundadır ve şifresiz `sudo` kullanılır.
- **`ImageOS`** değeri, GitHub tarafından barındırılan runner'larla eşleşen `ubuntu24` veya `ubuntu22` şeklindedir.
- **Android.** `ANDROID_HOME` ve `ANDROID_SDK_ROOT` SDK'yı işaret eder. Emülatör önceden yüklenmemiştir; bkz. <.localized_link href="/guides/features/runners#android-emulators">Android emülatörleri</.localized_link>.
- **Yerel ayar.** `LANG` ve `LC_ALL` değerleri `C.UTF-8` şeklindedir ve `DEBIAN_FRONTEND` değeri `noninteractive` olduğundan `sudo apt-get install` istemde bulunmaz.

### Dahil değil {#linux-not-included}

Linux görüntüsü, GitHub'ın önceden yüklediği her dil araç zinciri yerine derleme temellerini kapsar. İşinizin ihtiyaç duyduklarını olağan kurulum eylemleriyle (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise ile veya `apt-get` kullanarak kurun:

- Java, Node.js, Go, Ruby, .NET ve Rust gibi **Dil çalışma zamanları**.
- **Android NDK.** İhtiyacınız olan sürümü `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` ile kurun. `ANDROID_NDK_HOME` ayarlanmamış bırakılır, böylece derleme olmayan bir NDK'yı işaret etmek yerine açıkça başarısız olur.
- **Tarayıcılar** ve `kubectl`, Helm ile `gh` dışındaki bulut CLI'ları.

Bir araç zincirini her seferinde kurmak yerine işler arasında korumak için onu bir <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimine</.localized_link> yerleştirin.

## Görüntü güncellemeleri {#image-updates}

Apple yeni bir Xcode veya beta yayınladığında, CI ajanları güncellendiğinde ve görüntülerin kendilerini değiştirdiğimizde görüntüler yeniden oluşturulur. Bir iş her zaman eksiksiz, test edilmiş bir görüntü üzerinde çalışır: yeni görüntüler filoya kademeli olarak dağıtılır ve bir iş çalışırken asla değişmez.

İş akışınızın güvendiği bir araç eksikse [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack'inde](https://slack.tuist.dev) sorun.
