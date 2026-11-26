---
{
  "title": "Görüntüler",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Çalıştırıcılarında önceden yüklü olanlar: Xcode, simülatörler ve Metal araç zinciri içeren macOS görüntüleri ile Docker ve Android SDK içeren Ubuntu görüntüleri."
}
---
# Görüntüler {#images}

Her Tuist Runners işi, bir runner görüntüsünden başlatılan yeni bir sanal makinede çalışır. <.localized_link href="/guides/features/runners/profiles">Profiliniz</.localized_link> görüntüyü seçer: platformu, macOS'taki Xcode sürümünü ve Linux'taki Ubuntu dağıtımını. İş bittiğinde VM atılır, bu nedenle bir işin kurduğu her şey sonraki iş için silinir.

Görüntüler, iş akışları için önemli olan noktalarda GitHub tarafından barındırılan runner'ları takip eder: aynı kullanıcı, ev dizini ve çalışma alanı yolları, `ImageOS`, şifresiz `sudo` ve çoğu iOS, macOS ve Linux iş akışının beklediği araçlar. GitHub'ınkilerden kasıtlı olarak daha küçüktürler, bu nedenle farklılıklar her platform için aşağıda listelenmiştir.

## Bir görüntü seçme {#choosing-an-image}

- **Xcode, Apple SDK'leri veya simülatörler:** projenizin derlendiği Xcode sürümüne sabitlenmiş bir macOS profili.
- **Docker, Android derlemeleri ve emülatörler veya diğer Linux araçları:** Ubuntu 24.04 üzerinde bir Linux profili.
- **Henüz Ubuntu 24.04'ü desteklemeyen bir bağımlılık:** Ubuntu 22.04 üzerinde bir Linux profili.

macOS'ta görüntüyü değil, Xcode'u seçersiniz: her Xcode sürümü kendi görüntüsüdür ve `26.4.1` sürümüne sabitlenmiş bir profil her zaman Xcode 26.4.1 ile oluşturulan görüntüde çalışır. İki Xcode sürümü çalıştırmak için her biri için bir profil oluşturun.

## macOS {#macos}

macOS runner'lar, profilin **İşletim sistemi** alanında belirtilen **macOS 26 Tahoe** veya **macOS 27 Golden Gate** üzerinde çalışan Apple silicon (arm64) sanal makinelerdir. Seçim mevcut olmadan önce oluşturulan profiller Tahoe üzerinde çalışır. Her Xcode, her macOS sürümü için ayrı ayrı oluşturulur, bu nedenle bir profilin seçebileceği Xcode sürümleri işletim sistemine bağlıdır. Bir runner'ın adı tam macOS sürümünü içerir, örneğin `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…` ve işin **İşi ayarla** adımında görünür.

### Xcode {#xcode}

Her görüntü **tam olarak bir Xcode** içerir; bu, `xcode-select` ile seçilir, böylece `xcodebuild` ve `xcrun` bunu bir kurulum adımı olmadan kullanır. Bu, iş zamanında geçiş yapmak için birkaç Xcode sürümü sunan GitHub tarafından barındırılan görüntülerden ana farktır. Mevcut sürümler:

{{runner_macos_xcode_versions}}

- **Yol.** Xcode `/Applications/Xcode_<version>.app` konumundadır. Yama bileşeni içeren bir sürüm için `/Applications/Xcode_<major>.<minor>.app` aynı paketi işaret eder, bu nedenle `Xcode_26.4.app` değeri `Xcode_26.4.1.app` olarak çözümlenir. GitHub tarzı bir yolu sabit kodlayan veya bununla `xcode-select -s` çağıran iş akışları çalışmaya devam eder.
- **Simülatörler.** O Xcode ile birlikte gelen iOS, tvOS, watchOS ve visionOS simülatör çalışma zamanları görüntüye indirilir, böylece ilk `xcodebuild test` bunları almak zorunda kalmaz.
- **Metal araç zinciri.** Xcode 26'dan beri Metal derleyicisi Xcode ile birlikte gelmez ve ayrı olarak indirilmesi gerekir. Her görüntü, Xcode'una uygun Metal araç zincirini içerir ve işlerin çalıştığı kullanıcı için kurulur, böylece `xcrun metal` ve `.metal` kaynaklarına sahip projeler `xcodebuild -downloadComponent MetalToolchain` çalıştırmadan derlenir.
- **Beta sürümleri.** Beta profilleri (örneğin `27.3-beta`) o sürümün en son beta sürümünü takip eder. Apple yeni bir beta yayınladığında, görüntü yeniden oluşturulur ve profil sizin tarafınızdan herhangi bir değişiklik yapılmadan buna geçer.

### Önceden yüklenmiş yazılım {#macos-software}

- **Apple araçları:** Xcode (görüntü başına bir tane), simülatör çalışma zamanları, Metal araç zinciri, `xcodes`, `xcbeautify`
- **Swift ve iOS araçları:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **Cihazlar:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **Diller ve çalışma zamanları:** Bundler ile `rbenv` aracılığıyla Ruby (2.7 ve en son iki 3.x sürümü, en yenisi varsayılan olarak), npm, Yarn ve pnpm ile Node.js 24, Go, Java 21 (Temurin, `JAVA_HOME` olarak ayarlanmış)
- **Paket ve sürüm yöneticileri:** Homebrew, mise
- **Sürüm kontrolü:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **Yardımcı programlar:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI ajanları:** GitHub Actions runner, Buildkite agent, Bitrise agent ve CLI, GitLab job executor
- **Diğer:** Rosetta 2, `safaridriver` etkin

Araç sürümleri görüntü oluşturulduğunda Homebrew'den gelir ve görüntüler düzenli olarak yeniden oluşturulur. Bir runner'daki tam sürümü görmek için bir adımda yazdırın, örneğin `swiftlint version` veya `xcodebuild -version`.

### Ortam {#macos-environment}

- **Kullanıcı ve yollar.** İşler `runner` olarak çalışır, ev dizini `/Users/runner` ve çalışma alanı `/Users/runner/work` olup, GitHub tarafından barındırılan runner'larla aynı yollardır, bu nedenle bunları sabit kodlayan eylemler çalışır.
- **`sudo`.** Şifresiz. VM yalnızca işinize aittir.
- **Homebrew.** Ön ek (`/opt/homebrew`) `runner` tarafından sahiplenilir, bu nedenle `brew install <formula>` `sudo` olmadan çalışır. `HOMEBREW_NO_AUTO_UPDATE` ayarlanmıştır.
- **Kabuk.** Adımlar bir oturum açma kabuğunda çalışır, bu nedenle Homebrew, `rbenv` ve Node.js `PATH` üzerindedir. `LANG` değeri `en_US.UTF-8` şeklindedir.
- **`ImageOS`** değeri, GitHub tarafından barındırılan runner'larda olduğu gibi `macos26` şeklindedir; bu, önceden oluşturulmuş ikili dosyaları buna göre seçen kurulum eylemleri içindir.
- **Sertifikalar.** Apple'ın WWDR (G3) ve Developer ID (G2) ara sertifikaları, imzalama ve onaylama için sistem güven deposundadır.
- **Gizlilik izinleri.** GitHub tarafından barındırılan görüntülerde olduğu gibi, iki macOS gizlilik onayı önceden verilir: `create-dmg` ve `osascript` öğelerinin ihtiyaç duyduğu Apple Events aracılığıyla Finder betiklemesi ve UI testlerinde ses kaydeden uygulamaların ihtiyaç duyduğu iOS Simülatörü'nün mikrofona erişimi. Bir simülatör içindeki izinler, örneğin `simctl privacy`, işinizin sorumluluğunda kalır.
- **Disk.** Her iş en az 100 GB boş disk alanıyla başlar.

### Dahil değil {#macos-not-included}

- **Tuist CLI.** Projenizin sürümü kontrol etmesi için bunu iş sırasında, örneğin mise ile kurun.
- **Diğer Xcode sürümleri.** `xcode-select` yerine Xcode sürümü başına bir profil kullanın.
- **Docker.** macOS runner'larında Docker daemon yoktur. Bir Linux profili kullanın; bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **GitHub'ın macOS'ta paketlediği araç zincirleri**, iOS derlemelerinin nadiren ihtiyaç duyduğu diğer Java sürümleri, Android SDK, .NET, Rust, Python sürümleri veya tarayıcılar gibi öğelerdir. Bunları bir adımda Homebrew, mise veya bir kurulum eylemi ile kurun.

## Linux {#linux}

Linux runner'lar, profil tarafından seçilen **Ubuntu 24.04** veya **Ubuntu 22.04** üzerinde çalışan x86_64 (amd64) sanal makinelerdir. Bir sürümün nasıl seçileceğini öğrenmek için bkz. <.localized_link href="/guides/features/runners/profiles#linux">Profiller</.localized_link>.

### Önceden yüklenmiş yazılımlar {#linux-software}

- **Derleme araç zinciri:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **Geliştirme başlık dosyaları:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** `pip` ve `venv` ile birlikte Python 3 (Ubuntu sürümünün sürümü)
- **Konteynerler:** Buildx ve Compose içeren Docker CLI; daemon işle birlikte çalışır (bkz. <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Komut satırı araçları, platform araçları ve API 34 ve üzeri her platform ve derleme araçları sürümü ile birlikte `/usr/local/lib/android/sdk` konumunda Android SDK, lisanslar kabul edilmiş durumda
- **Sürüm kontrolü:** Git, Git LFS, OpenSSH istemcisi, GitHub CLI (`gh`)
- **Veritabanı istemcileri:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **Arşivler:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **Yardımcı programlar:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI ajanları:** GitHub Actions runner, Buildkite agent, Bitrise agent and CLI, GitLab job executor

### Ortam {#linux-environment}

- **Kullanıcı ve yollar.** İşler, ev dizini `/home/runner` olan `docker` grubunda, şifresiz `sudo` ile `runner` (UID 1000) olarak çalışır.
- **`ImageOS`** değeri, GitHub tarafından barındırılan runner'larla eşleşen `ubuntu24` veya `ubuntu22` şeklindedir.
- **Android.** `ANDROID_HOME` ve `ANDROID_SDK_ROOT` SDK'yı işaret eder. Emülatör önceden yüklenmemiştir; bkz. <.localized_link href="/guides/features/runners#android-emulators">Android emülatörleri</.localized_link>.
- **Yerel ayar.** `LANG` ve `LC_ALL` değerleri `C.UTF-8` şeklindedir ve `DEBIAN_FRONTEND` değeri `noninteractive` olduğundan `sudo apt-get install` istemde bulunmaz.

### Dahil değil {#linux-not-included}

Linux görüntüsü, GitHub'ın önceden yüklediği her dil araç zinciri yerine derleme temellerini kapsar. İşinizin ihtiyaç duyduklarını olağan kurulum eylemleri (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise veya `apt-get` ile kurun:

- Java, Node.js, Go, Ruby, .NET ve Rust gibi **dil çalışma zamanları**.
- **Android NDK.** İhtiyacınız olan sürümü `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"` ile kurun. `ANDROID_NDK_HOME` ayarlanmamış bırakılır, böylece olmayan bir NDK'yı işaret etmek yerine derleme açıkça başarısız olur.
- **Tarayıcılar** ve `kubectl`, Helm ile `gh` dışındaki bulut CLI'ları.

Bir araç zincirini her seferinde kurmak yerine işler arasında korumak için onu bir <.localized_link href="/guides/features/runners/cache-volumes">önbellek birimine</.localized_link> yerleştirin.

## Görüntü güncellemeleri {#image-updates}

Görüntüler, Apple yeni bir Xcode veya beta sürümü yayınladığında, CI ajanları güncellendiğinde ve görüntülerin kendilerini değiştirdiğimizde yeniden oluşturulur. Bir iş her zaman tamamlanmış, test edilmiş bir görüntü üzerinde çalışır: yeni görüntüler filoya kademeli olarak dağıtılır ve bir iş çalışırken asla değişmez.

İş akımınızın güvendiği bir araç eksikse, [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında sorun.
