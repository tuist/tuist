---
{
  "title": "გამოსახულებები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "რა არის წინასწარ დაყენებული Tuist გამშვებებზე: macOS გამოსახულებები Xcode-ით, სიმულატორებითა და Metal ინსტრუმენტების ჯაჭვით, და Ubuntu გამოსახულებები Docker-ითა და Android SDK-ით."
}
---
# გამოსახულებები {#images}

ყველა Tuist Runners-ის დავალება იწყება ახალ ვირტუალურ მანქანაში, რომელიც ჩატვირთულია რანერის გამოსახულებიდან. თქვენი <.localized_link href="/guides/features/runners/profiles">პროფილი</.localized_link> ირჩევს გამოსახულებას: პლატფორმას, Xcode-ის ვერსიას macOS-ზე და Ubuntu-ს გამოშვებას Linux-ზე. VM იშლება დავალების დასრულებისას, ამიტომ ყველაფერი, რაც დავალებამ დააინსტალირა, შემდეგი დავალებისთვის აღარ არსებობს.

გამოსახულებები მიჰყვებიან GitHub-ზე განთავსებულ რანერებს იმ ასპექტებში, რომლებიც მნიშვნელოვანია სამუშაო პროცესებისთვის: იგივე მომხმარებელი, საწყისი და სამუშაო სივრცის გზები, `ImageOS`, პაროლის გარეშე `sudo`, და ხელსაწყოები, რომლებსაც iOS, macOS და Linux-ის სამუშაო პროცესების უმეტესობა ელის. ისინი განზრახ უფრო მცირე ზომისაა, ვიდრე GitHub-ის, ამიტომ განსხვავებები ჩამოთვლილია თითოეული პლატფორმისთვის ქვემოთ.

## გამოსახულების არჩევა {#choosing-an-image}

- **Xcode, Apple SDK-ები ან სიმულატორები:** macOS პროფილი, მიბმული Xcode-ის იმ ვერსიაზე, რომლითაც თქვენი პროექტი კომპილდება.
- **Docker, Android-ის ბილდები და ემულატორები, ან სხვა Linux-ის ხელსაწყოები:** Linux პროფილი Ubuntu 24.04-ზე.
- **დამოკიდებულება, რომელიც ჯერ არ უჭერს მხარს Ubuntu 24.04-ს:** Linux პროფილი Ubuntu 22.04-ზე.

macOS-ზე თქვენ ირჩევთ Xcode-ს და არა გამოსახულებას: Xcode-ის თითოეული ვერსია წარმოადგენს ცალკე გამოსახულებას და პროფილი, მიბმული `26.4.1`-ზე, ყოველთვის გაეშვება Xcode 26.4.1-ით აგებულ გამოსახულებაზე. ორი Xcode ვერსიის გასაშვებად, შექმენით ცალკე პროფილი თითოეულისთვის.

## macOS {#macos}

macOS რანერები არის Apple silicon (arm64) ვირტუალური მანქანები, რომლებზეც გაშვებულია **macOS 26 Tahoe**. რანერის სახელი შეიცავს macOS-ის ზუსტ ვერსიას, მაგალითად `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-…`, და ჩანს დავალების **დავალების დაყენება** ეტაპზე.

### Xcode {#xcode}

თითოეული გამოსახულება შეიცავს **ზუსტად ერთ Xcode-ს**, რომელიც არჩეულია `xcode-select`-ით, ამიტომ `xcodebuild` და `xcrun` იყენებენ მას დაყენების ეტაპის გარეშე. ეს არის მთავარი განსხვავება GitHub-ზე განთავსებული გამოსახულებებისგან, რომლებიც რამდენიმე Xcode ვერსიას შეიცავენ დავალების დროს გადასართავად. ხელმისაწვდომი ვერსიები:

{{runner_macos_xcode_versions}}

- **გზა.** Xcode მდებარეობს `/Applications/Xcode_<version>.app`-ზე. პატჩის კომპონენტის მქონე ვერსიისთვის, `/Applications/Xcode_<major>.<minor>.app` მიუთითებს იმავე ბანდლზე, ამიტომ `Xcode_26.4.app` გადაიხსნება როგორც `Xcode_26.4.1.app`. სამუშაო პროცესები, რომლებიც აკოდირებენ GitHub-ის სტილის გზას ან იძახებენ `xcode-select -s`-ს მისით, განაგრძობენ მუშაობას.
- **სიმულატორები.** iOS, tvOS, watchOS და visionOS სიმულატორის გარემოები, რომლებიც მოყვება ამ Xcode-ს, ჩამოტვირთულია გამოსახულებაში, ამიტომ პირველ `xcodebuild test`-ს არ სჭირდება მათი ჩამოტვირთვა.
- **Metal ინსტრუმენტთა ჯაჭვი.** Xcode 26-დან, Metal კომპილატორი არ არის ჩაშენებული Xcode-ში და ცალკე უნდა ჩამოიტვირთოს. ყველა გამოსახულება შეიცავს Metal ინსტრუმენტთა ჯაჭვს, რომელიც შეესაბამება მის Xcode-ს და დაინსტალირებულია იმ მომხმარებლისთვის, რომლის სახელითაც დავალებები გაეშვება, ამიტომ `xcrun metal` და პროექტები `.metal` წყაროებით კომპილდება `xcodebuild -downloadComponent MetalToolchain`-ის გაშვების გარეშე.
- **ბეტა ვერსიები.** ბეტა პროფილები (მაგალითად `27.3-beta`) ადევნებენ თვალს იმ გამოშვების უახლეს ბეტას. როდესაც Apple ახალ ბეტას გამოუშვებს, გამოსახულება თავიდან აიგება და პროფილი გადავა მასზე თქვენი მხრიდან ცვლილებების გარეშე.

### წინასწარ დაინსტალირებული პროგრამული უზრუნველყოფა {#macos-software}

- **Apple-ის ხელსაწყოები:** Xcode (ერთი თითოეულ გამოსახულებაზე), სიმულატორის გარემოები, Metal ინსტრუმენტთა ჯაჭვი, `xcodes`, `xcbeautify`
- **Swift და iOS ხელსაწყოები:** SwiftLint, SwiftFormat, SwiftGen, LicensePlist, Mint, Carthage, CocoaPods, fastlane
- **მოწყობილობები:** `libimobiledevice`, `ideviceinstaller`, `ios-deploy`
- **ენები და გარემოები:** Ruby `rbenv`-ის მეშვეობით (2.7 და ორი უახლესი 3.x გამოშვება, უახლესი როგორც ნაგულისხმევი) Bundler-თან ერთად, Node.js 24 npm, Yarn და pnpm-თან ერთად
- **პაკეტების და ვერსიების მენეჯერები:** Homebrew, mise
- **ვერსიების კონტროლი:** Git, Git LFS, Git Credential Manager, GitHub CLI (`gh`)
- **სახმარები პროგრამები:** `jq`, `yq`, `curl`, `wget`, `zip`/`unzip`, CMake, GCC, AWS CLI
- **CI აგენტები:** GitHub Actions runner, Buildkite agent, Bitrise agent და CLI, GitLab job executor
- **სხვა:** Rosetta 2, `safaridriver` ჩართული

ხელსაწყოების ვერსიები მოდის Homebrew-დან გამოსახულების აგებისას და გამოსახულებები რეგულარულად თავიდან აიგება. რანერზე ზუსტი ვერსიის სანახავად, დაბეჭდეთ ის ეტაპზე, მაგალითად `swiftlint version` ან `xcodebuild -version`.

### გარემო {#macos-environment}

- **მომხმარებელი და გზები.** დავალებები გაეშვება `runner`-ის სახელით, საწყისი დირექტორიით `/Users/runner` და სამუშაო სივრცით `/Users/runner/work`, იგივე გზებით, რაც GitHub-ზე განთავსებულ რანერებზე, ამიტომ მოქმედებები, რომლებიც მათ აკოდირებენ, მუშაობენ.
- **`sudo`.** პაროლის გარეშე. VM ეკუთვნის მხოლოდ თქვენს დავალებას.
- **Homebrew.** პრეფიქსი (`/opt/homebrew`) ეკუთვნის `runner`-ს, ამიტომ `brew install <formula>` მუშაობს `sudo`-ის გარეშე. `HOMEBREW_NO_AUTO_UPDATE` დაყენებულია.
- **Shell.** ეტაპები გაეშვება login shell-ში, ამიტომ Homebrew, `rbenv` და Node.js არიან `PATH`-ზე. `LANG` არის `en_US.UTF-8`.
- **`ImageOS`** არის `macos26`, როგორც GitHub-ზე განთავსებულ რანერებზე, დაყენების მოქმედებებისთვის, რომლებიც ირჩევენ წინასწარ აგებულ ბინარებს მის მიხედვით.
- **სერტიფიკატები.** Apple-ის WWDR (G3) და Developer ID (G2) შუალედური სერტიფიკატები არიან სისტემის სანდოობის საცავში ხელმოწერისა და ნოტარიზაციისთვის.
- **კონფიდენციალურობის ნებართვები.** ორი macOS კონფიდენციალურობის დამტკიცება წინასწარ არის გაცემული, როგორც GitHub-ზე განთავსებულ გამოსახულებებზე: Finder-ის სკრიპტინგი Apple Events-ის მეშვეობით, რაც `create-dmg`-ს და `osascript`-ს სჭირდება, და iOS სიმულატორის წვდომა მიკროფონზე, რაც UI ტესტებში აუდიოს ჩამწერ აპლიკაციებს სჭირდებათ. ნებართვები სიმულატორის შიგნით, როგორიცაა `simctl privacy`, რჩება თქვენი დავალების პასუხისმგებლობად.
- **დისკი.** თითოეული დავალება იწყება მინიმუმ 100 GB თავისუფალი დისკის სივრცით.

### არ არის შეტანილი {#macos-not-included}

- **Tuist CLI.** დააინსტალირეთ ის დავალებაში, მაგალითად mise-ით, რათა თქვენმა პროექტმა აკონტროლოს ვერსია.
- **სხვა Xcode ვერსიები.** გამოიყენეთ პროფილი თითოეული Xcode ვერსიისთვის `xcode-select`-ის ნაცვლად.
- **Docker.** macOS რანერებს არ აქვთ Docker daemon. გამოიყენეთ Linux პროფილი; იხილეთ <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>.
- **GitHub-ის მიერ macOS-ზე შეკრული ინსტრუმენტების ჯაჭვები**, რომლებიც iOS აგებას იშვიათად სჭირდება, როგორიცაა Java, Android SDK, .NET, Rust, Python ვერსიები ან ბრაუზერები. დააინსტალირეთ ისინი ეტაპში Homebrew-ით, mise-ით ან დაყენების მოქმედებით.

## Linux {#linux}

Linux რანერები არიან x86_64 (amd64) ვირტუალური მანქანები **Ubuntu 24.04**-ზე ან **Ubuntu 22.04**-ზე, პროფილის მიხედვით შერჩეული. იხილეთ <.localized_link href="/guides/features/runners/profiles#linux">პროფილები</.localized_link> რელიზის შერჩევისთვის.

### წინასწარ დაინსტალირებული პროგრამული უზრუნველყოფა {#linux-software}

- **აგების ინსტრუმენტების ჯაჭვი:** `build-essential` (GCC, G++, make), autoconf, automake, libtool, `pkg-config`, CMake, Ninja, m4, bison, flex, gettext
- **დეველოპერული სათაურები:** OpenSSL, libffi, zlib, bzip2, readline, SQLite, ncurses, libxml2, libxslt, libyaml, libcurl, uuid
- **Python:** Python 3 `pip`-ით და `venv`-ით (Ubuntu რელიზის ვერსია)
- **კონტეინერები:** Docker CLI Buildx-ით და Compose-ით; daemon გაეშვება დავალების პარალელურად (იხილეთ <.localized_link href="/guides/features/runners/docker">Docker</.localized_link>)
- **Kubernetes:** `kubectl`, Helm
- **Android:** Android SDK `/usr/local/lib/android/sdk`-ზე ბრძანების ხაზის ინსტრუმენტებით, platform-tools-ით და ყოველი პლატფორმისა და build-tools რელიზით API 34-დან ზემოთ, მიღებული ლიცენზიებით
- **ვერსიის კონტროლი:** Git, Git LFS, OpenSSH კლიენტი, GitHub CLI (`gh`)
- **მონაცემთა ბაზის კლიენტები:** PostgreSQL, MariaDB, Redis (`redis-cli`), SQLite
- **არქივები:** `tar`, `zip`/`unzip`, `xz`, `bzip2`, `p7zip`, `zstd`
- **სახმარები:** `curl`, `wget`, `jq`, ripgrep, `fd`, `tree`, `less`, `vim`, HTTPie, `netcat`, `dig`, `ip`, `ping`, `file`
- **CI აგენტები:** GitHub Actions runner, Buildkite agent, Bitrise agent და CLI, GitLab job executor

### გარემო {#linux-environment}

- **მომხმარებელი და გზები.** დავალებები გაეშვება `runner`-ის სახელით (UID 1000) საწყისი საქაღალდით `/home/runner`, `docker` ჯგუფში, პაროლის გარეშე `sudo`-ით.
- **`ImageOS`** არის `ubuntu24` ან `ubuntu22`, შესაბამისობაში GitHub-ზე განთავსებულ რანერებთან.
- **Android.** `ANDROID_HOME` და `ANDROID_SDK_ROOT` მიუთითებს SDK-ზე. ემულატორი წინასწარ არ არის დაინსტალირებული; იხილეთ <.localized_link href="/guides/features/runners#android-emulators">Android ემულატორები</.localized_link>.
- **ლოკალი.** `LANG` და `LC_ALL` არის `C.UTF-8`, და `DEBIAN_FRONTEND` არის `noninteractive`, ამიტომ `sudo apt-get install` არ ითხოვს შეყვანას.

### არ არის შეტანილი {#linux-not-included}

Linux გამოსახულება ფარავს აგების საბაზისო ნაწილს და არა ყოველ ენის ინსტრუმენტების ჯაჭვს, რომელსაც GitHub წინასწარ აინსტალირებს. დააინსტალირეთ თქვენი დავალებისთვის საჭირო ჩვეულებრივი დაყენების მოქმედებებით (`actions/setup-java`, `actions/setup-node`, `actions/setup-go`, `ruby/setup-ruby`), mise-ით ან `apt-get`-ით:

- **ენის გარემოები**, როგორიცაა Java, Node.js, Go, Ruby, .NET და Rust.
- **Android NDK.** დააინსტალირეთ საჭირო ვერსია `"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "ndk;<version>"`-ით. `ANDROID_NDK_HOME` რჩება დაუყენებელი, რათა აგება ცხადად ჩავარდეს და არ მიუთითებდეს არარსებულ NDK-ზე.
- **ბრაუზერები** და ღრუბლის CLIs, `kubectl`-ის, Helm-ის და `gh`-ის გარდა.

იმისთვის, რომ ინსტრუმენტების ჯაჭვი შეინარჩუნოთ დავალებებს შორის ყოველ ჯერზე ინსტალაციის ნაცვლად, მოათავსეთ ის <.localized_link href="/guides/features/runners/cache-volumes">ქეშის ტომზე</.localized_link>.

## გამოსახულების განახლებები {#image-updates}

გამოსახულებები თავიდან აიგება, როცა Apple გამოუშვებს ახალ Xcode-ს ან ბეტას, როცა CI აგენტები განახლდება და როცა ჩვენ შევცვლით თავად გამოსახულებებს. დავალება ყოველთვის გაეშვება სრულ, შემოწმებულ გამოსახულებაზე: ახალი გამოსახულებები თანდათანობით ნაწილდება ფლოტზე და არასდროს იცვლება დავალების შესრულებისას.

თუ თქვენს სამუშაო პროცესს საჭირო ინსტრუმენტი აკლია, [დაგვიკავშირდით](mailto:contact@tuist.dev) ან იკითხეთ [საზოგადოების Slack-ში](https://slack.tuist.dev).
