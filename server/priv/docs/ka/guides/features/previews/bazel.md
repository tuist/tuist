---
{
  "title": "Bazel-ის პრივიუები",
  "titleTemplate": ":title · პრივიუები · Tuist",
  "description": "გამოაქვეყნეთ Android აპლიკაციები, Apple აპლიკაციები და კომანდური ხაზის ინსტრუმენტები Bazel-იდან პრივიუების სახით."
}
---
# Bazel-ის პრევიუები

გამოაქვეყნეთ Android APK, Apple სიმულატორისა და macOS აპლიკაციები, ასევე ბრძანების ხაზის ინსტრუმენტები თქვენი არსებული Bazel სამიზნეებიდან. დაამატეთ პრევიუს სამიზნე თითოეული გატანისთვის, რომლის გაზიარებაც გსურთ; თქვენი ჩვეულებრივი ბილდები უცვლელი დარჩება.

## მორგება

დაამატეთ [`rules_tuist` Tuist-ის რეპოზიტორიიდან](https://github.com/tuist/tuist/tree/main/bazel) ფაილში `MODULE.bazel`, მიმაგრებით იმ კომიტზე, რომლის გამოყენებაც გსურთ:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

შეინარჩუნეთ თქვენი არსებული აპლიკაციის სამიზნეები, ნატიური SDK-ები და ხელმოწერის კონფიგურაცია. Bazel უზრუნველყოფს გამოქვეყნების ინსტრუმენტებს.

შედით პირდაპირ Bazel-იდან:

```bash
bazel run @rules_tuist//:login
```

ეს იზიარებს სერთიფიკატებს Tuist CLI-თან და Gradle პლაგინთან; არსებული შესვლაც მუშაობს. CI-ზე გამოიყენეთ `TUIST_TOKEN` ან გაუშვით შესვლის სამიზნე Tuist-ის <.localized_link href="/guides/integrations/continuous-integration">OIDC ავთენტიკაციით</.localized_link>. არასდროს მოათავსოთ სერთიფიკატები BUILD ფაილებში ან წესების ატრიბუტებში. გადაეცით `-- --url https://tuist.example.com` self-hosted ეგზემპლარში შესასვლელად.

ჩატვირთეთ მხოლოდ ის ადაპტერი, რომელიც გჭირდებათ თქვენს `BUILD.bazel`-ში:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Apple აპლიკაციებისთვის:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

შესრულებადი სამიზნეებისთვის, როგორიცაა `cc_binary`:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

შესრულებადი პრევიუ მოიცავს სამიზნის განცხადებულ runtime ფაილებს. განაცხადეთ ბიბლიოთეკები და რესურსები, რომლებიც თქვენს ინსტრუმენტს სჭირდება მის Bazel სამიზნეში, და გამოიყენეთ გზები, რომლებიც მუშაობენ თქვენი ბილდის დირექტორიის გარეთ.

## აწყობა და გამოქვეყნება

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

ჩაანაცვლეთ აპლიკაციისა და სიმულატორის პლატფორმის ლეიბლები თქვენით. გადაეცით `--url` self-hosted Tuist წყაროსთვის და `--revision` Git კომიტის დასაკავშირებლად.

გადაეცით `--publish --project account/project` წარმატებული ბილდის გასაზიარებლად. `--publish`-ის გარეშე, ან `--no-publish`-ით, არაფერი აიტვირთება და შესვლა არ არის საჭირო. ჩვეულებრივი `bazel build` არასდროს აქვეყნებს, მათ შორის ქეშის მოხვედრების შემთხვევაშიც. `tuist bazel setup` ააქტიურებს ქეშირებას და ინსაიტებს, არა გამოქვეყნებას.

## მხარდაჭერილი გატანები

- **Android:** ხელმოწერილი აპლიკაციის APK-ები, debug ბილდების ჩათვლით. დააინსტალირეთ Android SDK build-tools და ბრძანების ხაზის ინსტრუმენტები, და დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`. ტესტის APK-ები და Android App Bundles მხარდაჭერილი არ არის.
- **Apple:** ad-hoc ხელმოწერილი სიმულატორისა და macOS აპლიკაციები, აწყობილი და ვერიფიცირებული macOS-ზე. ფიზიკური მოწყობილობის ბილდები, ფრეიმვორქები, გაფართოებები და ტესტები მხარდაჭერილი არ არის. გამოიყენეთ archive გატანა ექსპერიმენტული tree archives-ის ნაცვლად.
- **ბრძანების ხაზის ინსტრუმენტები:** macOS ან Linux შესრულებადი ფაილები arm64 ან x86_64-ისთვის, უნივერსალური macOS ბინარების ჩათვლით. სკრიპტებს სჭირდებათ shebang და ინტერპრეტატორი მიმღების სისტემაზე. განაცხადეთ runtime დამოკიდებულებები თქვენს სამიზნეში; Tuist არ აინსტალირებს დაკარგულ ბიბლიოთეკებს ან ენის runtime-ებს.

## ქეშის განმეორება, შეცდომები და შენახვა

იგივე გამოქვეყნების გამეორება ხელახლა იყენებს არსებულ პრევიუს მისი ხელახლა ატვირთვის გარეშე, მაშინაც კი, როცა Bazel აღადგენს ბილდს ქეშიდან. გატანის, ტრეკის ან რევიზიის ცვლილება ქმნის ახალ გამოქვეყნებას. ატვირთვის შეცდომა აუქმებს ბრძანებას; შეგიძლიათ ხელახლა გაუშვათ იმის შესამოწმებლად, დასრულდა თუ არა გამოქვეყნება ხელახლა ცდამდე.

ბრძანება ბმავს თქვენი პროექტის პრევიუებზე, სადაც დამუშავებას შეიძლება რამდენიმე წამი დასჭირდეს. პრევიუები იყენებენ პროექტის ნაგულისხმევ ხილვადობას.

არტიფაქტების გამოქვეყნებები იწურება 30 დღის შემდეგ hosted Tuist-ზე. Self-hosted ეგზემპლარები იყენებენ `TUIST_APP_PREVIEW_RETENTION_DAYS`; მისი დაუყენებლობა თიშავს ვადას ამ ოჯახისთვის. ვადაგასული გამოქვეყნების ჩანაწერების აღდგენა იგივე განზრახვის განმეორებით შეუძლებელია.

იხილეთ <.localized_link href="/guides/features/previews#run-a-preview">პრევიუს გაშვება</.localized_link> გამოქვეყნებული ბილდების გასაშვებად, წვდომისთვის, ტრეკებისა და README ბეჯებისთვის.

## Apple პრევიუები

Apple სიმულატორისა და macOS პრევიუებისთვის, იხილეთ <.localized_link href="/guides/features/previews/run/macos">Tuist macOS თანმხლები აპლიკაციის ინსტრუქციები</.localized_link>. ეს არ ცვლის Bazel-ის აპლიკაციის შესაბამისობის ან ხელმოწერის მოთხოვნებს.

## დაკავშირებული სამუშაო ნაკადები {#publish-from-once}

არსებულ Struo ინტეგრაციებს აქვთ ცალკე <.localized_link href="/guides/features/previews/struo">არტიფაქტების გამოქვეყნების სახელმძღვანელო</.localized_link>. ორივე სამუშაო ნაკადი ინარჩუნებს გამოქვეყნებას ცალკე ქეშირებული გრაფის შესრულებისგან.
