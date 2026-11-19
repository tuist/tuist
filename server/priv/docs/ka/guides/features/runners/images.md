---
{
  "title": "გამოსახულებები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "რა არის წინასწარ დაყენებული Tuist გამშვებებზე: macOS-ის გამოსახულებები Xcode-ით, სიმულატორებითა და Metal-ის ინსტრუმენტთა ჯაჭვით, და Ubuntu-ს გამოსახულებები Docker-ითა და Android SDK-ით."
}
---
# გამოსახულებები {#images}

Tuist Runners-ის ყოველი ამოცანა იწყება ახალ ვირტუალურ მანქანაში, რომელიც ჩატვირთულია რანერის გამოსახულებიდან. თქვენი <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> ირჩევს გამოსახულებას: პლატფორმას, Xcode-ის ვერსიას macOS-ზე და Ubuntu-ის გამოშვებას Linux-ზე. VM იშლება ამოცანის დასრულებისას, ამიტომ ყველაფერი, რასაც ამოცანა აყენებს, ქრება შემდეგი ამოცანისთვის.

გამოსახულებები მიჰყვებიან GitHub-ზე განთავსებულ რანერებს იქ, სადაც ეს მნიშვნელოვანია სამუშაო პროცესებისთვის: იგივე მომხმარებელი, საწყისი და სამუშაო სივრცის გზები, `ImageOS`, პაროლის გარეშე `sudo` და ხელსაწყოები, რომლებსაც iOS, macOS და Linux სამუშაო პროცესები ელიან. ისინი განზრახ უფრო მცირეა, ვიდრე GitHub-ის, ამიტომ განსხვავებები ჩამოთვლილია თითოეული პლატფორმისთვის ქვემოთ.

## გამოსახულების არჩევა {#choosing-an-image}

- **Xcode, Apple SDK ან სიმულატორები:** macOS პროფილი, მიბმული Xcode-ის იმ ვერსიაზე, რომლითაც თქვენი პროექტი კომპილდება.
- **Docker, Android ბილდები და ემულატორები, ან სხვა Linux ხელსაწყოები:** Linux პროფილი Ubuntu 24.04-ზე.
- **დამოკიდებულება, რომელიც ჯერ არ უჭერს მხარს Ubuntu 24.04-ს:** Linux პროფილი Ubuntu 22.04-ზე.

macOS-ზე თქვენ ირჩევთ Xcode-ს, არა გამოსახულებას: Xcode-ის თითოეული ვერსია არის საკუთარი გამოსახულება და პროფილი, მიბმული `26.4.1`-ზე, ყოველთვის გაეშვება გამოსახულებაზე, რომელიც აგებულია Xcode 26.4.1-ით. ორი Xcode ვერსიის გასაშვებად, შექმენით პროფილი თითოეულისთვის.

## macOS {#macos}

macOS რანერები არის Apple silicon (arm64) ვირტუალური მანქანები, რომლებიც მუშაობენ **macOS 26 Tahoe**-ზე. რანერის სახელი შეიცავს macOS-ის ზუსტ ვერსიას, მაგალითად `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, და ჩანს ამოცანის **ამოცანის მომზადება** ეტაპზე.

### Xcode {#xcode}

თითოეული გამოსახულება შეიცავს **ზუსტად ერთ Xcode-ს**, რომელიც არჩეულია `xcode-select`-ით, ასე რომ `xcodebuild` და `xcrun` იყენებენ მას მომზადების ეტაპის გარეშე. ეს არის მთავარი განსხვავება GitHub-ზე განთავსებული გამოსახულებებისგან, რომლებიც შეიცავს რამდენიმე Xcode ვერსიას, რათა ამოცანის დროს გადაერთონ მათ შორის. ხელმისაწვდომი ვერსიები:

{{runner_macos_xcode_versions}}

- **გზა.** Xcode მდებარეობს `/Applications/Xcode_<version>.app`-ზე. ვერსიისთვის პატჩის კომპონენტით, `/Applications/Xcode_<major>.<minor>.app` მიუთითებს იმავე ბანდლზე, ასე რომ `Xcode_26.4.app` გადაიხსნება როგორც `Xcode_26.4.1.app`. სამუშაო პროცესები, რომლებიც აკოდირებენ GitHub-ის სტილის გზას ან ურეკავენ `xcode-select -s`-ს მასთან, განაგრძობენ მუშაობას.
- **სიმულატორები.** iOS, tvOS, watchOS და visionOS სიმულატორის გარემოები, რომლებიც მოყვება ამ Xcode-ს, ჩამოტვირთულია გამოსახულებაში, ასე რომ პირველ `xcodebuild test`-ს არ უნდა ჩამოტვირთოს ისინი.
- **Metal ინსტრუმენტთა ჯაჭვი.** Xcode 26-დან, Metal კომპილატორი არ არის შეკრული Xcode-თან და უნდა ჩამოიტვირთოს ცალკე. ყოველი გამოსახულება შეიცავს Metal ინსტრუმენტთა ჯაჭვს, რომელიც შეესაბამება მის Xcode-ს, დაყენებულია იმ მომხმარებლისთვის, რომლის სახელითაც ამოცანები გაეშვება, ასე რომ `xcrun metal` და პროექტები `.metal` წყაროებით კომპილდება `xcodebuild -downloadComponent MetalToolchain`-ის გაშვების გარეშე.
- **ბეტა ვერსიები.** ბეტა პროფილები (მაგალითად `27.3-beta`) მიჰყვებიან ამ გამოშვების უახლეს ბეტას. როდესაც Apple გამოუშვებს ახალ ბეტას, გამოსახულება თავიდან აიგება და პროფილი გადავა მასზე თქვენი მხრიდან ცვლილების გარეშე.

### წინასწარ დაყენებული პროგრამული უზრუნველყოფა {#macos-software}

- **Apple ხელსაწყოები:** Xcode (თითოეულ გამოსახულებაზე ერთი), სიმულატორის გარემოები, Metal ინსტრუმენტთა ჯაჭვი, `xcodes`, `xcbeautify`
- **Swift და iOS ხელსაწყოები:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **მოწყობილობები:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **ენები და გარემოები:** Ruby `rbenv`-ის მეშვეობით (2.7 და ორი უახლესი 3.x გამოშვება, უახლესი როგორც ნაგულისხმევი) Bundler-ით, Node.js 24 npm-ით, Yarn-ით და pnpm-ით
- **პაკეტების და ვერსიების მენეჯერები:** Homebrew, mise
- **ვერსიების კონტროლი:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **სერვისული პროგრამები:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI აგენტები:** GitHub Actions runner, Buildkite agent, Bitrise agent და CLI, GitLab job executor
- **სხვა:** Rosetta 2, `safaridriver` ჩართული

ხელსაწყოების ვერსიები მოდის Homebrew-დან გამოსახულების აგებისას და გამოსახულებები რეგულარულად თავიდან აიგება. რანერზე ზუსტი ვერსიის სანახავად, დაბეჭდეთ ის ეტაპზე, მაგალითად `swiftlint version` ან `xcodebuild -version`.

### გარემო {#macos-environment}

- **მომხმარებელი და გზები.** ამოცანები გაეშვება `runner`-ის სახელით, საწყისი დირექტორიით `/Users/runner` და სამუშაო სივრცით `/Users/runner/work`, იგივე გზები, რაც GitHub-ზე განთავსებულ რანერებზე, ასე რომ მოქმედებები, რომლებიც აკოდირებენ მათ, მუშაობენ.
- **`sudo`.** პაროლის გარეშე. VM ეკუთვნის მხოლოდ თქვენს ამოცანას.
- **Homebrew.** პრეფიქსს (`/opt/homebrew`) ფლობს `runner`, ასე რომ `brew install <formula>` მუშაობს `sudo`-ის გარეშე. `HOMEBREW_NO_AUTO_UPDATE` დაყენებულია.
- **გარსი.** ეტაპები გაეშვება შესვლის გარსში, ასე რომ Homebrew, `rbenv` და Node.js არიან `PATH`-ზე. `LANG` არის `en_US.UTF-8`.
- **`ImageOS`** არის `macos26`, როგორც GitHub-ზე განთავსებულ რანერებზე, მომზადების მოქმედებებისთვის, რომლებიც ირჩევენ წინასწარ აგებულ ბინარებს მის მიხედვით.
- **სერტიფიკატები.** Apple-ის WWDR (G3) და Developer ID (G2) შუალედური სერტიფიკატები არიან სისტემის ნდობის საცავში ხელმოწერისა და ნოტარიზაციისთვის.
- **კონფიდენციალურობის ნებართვები.** ორი macOS კონფიდენციალურობის დამტკიცება წინასწარ არის გაცემული, როგორც GitHub-ზე განთავსებულ გამოსახულებებზე: Finder-ის სკრიპტირება Apple Events-ის მეშვეობით, რაც სჭირდება `create-dmg`-ს და `osascript`-ს, და iOS სიმულატორის წვდომა მიკროფონზე, რაც სჭირდება აპლიკაციებს, რომლებიც იწერენ აუდიოს UI ტესტებში. ნებართვები სიმულატორის შიგნით, როგორიცაა `simctl privacy`, რჩება თქვენი ამოცანის პასუხისმგებლობად.
- **დისკი.** თითოეული ამოცანა იწყება მინიმუმ 100 GB თავისუფალი დისკის სივრცით.

### არ არის შეტანილი {#macos-not-included}

- **Tuist CLI.** დააყენეთ ის ამოცანაში, მაგალითად mise-ით, რათა თქვენმა პროექტმა აკონტროლოს ვერსია.
- **სხვა Xcode ვერსიები.** გამოიყენეთ პროფილი თითოეული Xcode ვერსიისთვის `xcode-select`-ის ნაცვლად.
- **Docker.** macOS რანერებს არ აქვთ Docker daemon. გამოიყენეთ Linux პროფილი; იხილეთ <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **ინსტრუმენტები, რომლებსაც GitHub აერთიანებს macOS-ზე** და რომლებიც iOS აგებისას იშვიათად სჭირდება, როგორიცაა Java, Android SDK, .NET, Rust, Python ვერსიები ან ბრაუზერები. დააყენეთ ისინი ეტაპზე Homebrew-ით, mise-ით ან მომზადების მოქმედებით.

## Linux {#linux}

Linux რანერები არის x86_64 (amd64) ვირტუალური მანქანები **Ubuntu 24.04**-ზე ან **Ubuntu 22.04**-ზე, პროფილის მიხედვით შერჩეული. იხილეთ <.localized_link href="/guides/features/runners/profiles#linux">პროფილები</.localized_link> გამოცემის შერჩევისთვის.

### წინასწარ დაყენებული პროგრამული უზრუნველყოფა {#linux-software}

- **აგების ინსტრუმენტები:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **დეველოპერული სათაურები:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 `pip`-ით და `venv`-ით (Ubuntu გამოცემის ვერსია)
- **კონტეინერები:** Docker CLI Buildx-ით და Compose-ით; daemon გაეშვება ამოცანის გვერდით (იხილეთ <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK მდებარეობს `/usr/local/lib/android/sdk`-ზე ბრძანების ხაზის ინსტრუმენტებით, პლატფორმის ინსტრუმენტებით და ყველა პლატფორმისა და აგების ინსტრუმენტების გამოცემით API 34-დან ზემოთ, მიღებული ლიცენზიებით
- **ვერსიის კონტროლი:** Git, Git LFS, OpenSSH კლიენტი, GitHub CLI (`gh`)
- **მონაცემთა ბაზის კლიენტები:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **არქივები:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **სახმარები:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI აგენტები:** GitHub Actions runner, Buildkite agent, Bitrise agent და CLI, GitLab job executor

### გარემო {#linux-environment}

- **მომხმარებელი და გზები.** ამოცანები გაეშვება `runner`-ის სახელით (UID 1000) საწყისი საქაღალდით `/home/runner`, `docker` ჯგუფში, პაროლის გარეშე `sudo`-ით.
- **`ImageOS`** არის `ubuntu24` ან `ubuntu22`, შესაბამისობაში GitHub-ზე განთავსებულ რანერებთან.
- **Android.** `ANDROID_HOME` და `ANDROID_SDK_ROOT` მიუთითებს SDK-ზე. ემულატორი წინასწარ არ არის დაყენებული; იხილეთ <.localized_link href="/guides/features/runners#android-emulators">Android ემულატორები</.localized_link>.
- **ლოკალი.** `LANG` და `LC_ALL` არის `C.UTF-8`, და `DEBIAN_FRONTEND` არის `noninteractive`, ასე რომ `sudo apt-get install` არ ითხოვს შეყვანას.

### არ არის შეტანილი {#linux-not-included}

Linux გამოსახულება ფარავს აგების საბაზისო ნაწილს და არა ყველა ენის ინსტრუმენტს, რომელსაც GitHub წინასწარ აყენებს. დააყენეთ ის, რაც თქვენს ამოცანას სჭირდება, ჩვეულებრივი მომზადების მოქმედებებით (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise-ით ან `apt-get`-ით:

- **ენის გარსები**, როგორიცაა Java, Node.js, Go, Ruby, .NET და Rust.
- **Android NDK.** დააყენეთ საჭირო ვერსია `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`-ით. `ANDROID_NDK_HOME` რჩება დაუყენებელი, რათა აგება ცხადად ჩავარდეს და არ მიუთითებდეს არარსებულ NDK-ზე.
- **ბრაუზერები** და ღრუბლის CLIs, გარდა `kubectl`-ის, Helm-ისა და `gh`-ის.

ინსტრუმენტის შესანარჩუნებლად ამოცანებს შორის მის ყოველ ჯერზე დაყენების ნაცვლად, მოათავსეთ ის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომზე</.localized_link>.

## გამოსახულების განახლებები {#image-updates}

გამოსახულებები თავიდან აიგება, როდესაც Apple გამოუშვებს ახალ Xcode-ს ან ბეტას, როდესაც CI აგენტები განახლდება და როდესაც ჩვენ შევცვლით თავად გამოსახულებებს. ამოცანა ყოველთვის გაეშვება სრულ, შემოწმებულ გამოსახულებაზე: ახალი გამოსახულებები თანდათან ნაწილდება ფლოტზე და არ იცვლება ამოცანის შესრულების დროს.

თუ თქვენს სამუშაო პროცესს საჭირო ინსტრუმენტი აკლია, [დაგვიკავშირდით](mailto:contact@tuist.dev) ან იკითხეთ [საზოგადოების Slack-ში](https://slack.tuist.dev).
