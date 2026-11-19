---
{
  "title": "Bazel-ის პრევიუები",
  "titleTemplate": ":title · პრევიუები · Tuist",
  "description": "გამოაქვეყნეთ Android აპლიკაციები, Apple აპლიკაციები და კომანდური ხაზის ინსტრუმენტები Bazel-დან პრევიუების სახით."
}
---
# Bazel-ის პრივიუები

გამოაქვეყნეთ Android APK-ები, Apple სიმულატორისა და macOS აპლიკაციები და ბრძანების ხაზის ინსტრუმენტები თქვენი არსებული Bazel სამიზნეებიდან. დაამატეთ პრივიუს სამიზნე თითოეული შედეგისთვის, რომლის გაზიარებაც გსურთ; თქვენი ჩვეულებრივი ბილდები უცვლელი დარჩება.

## მოწყობა

დაამატეთ [`rules_tuist` Tuist-ის რეპოზიტორიიდან](https://github.com/tuist/tuist/tree/main/bazel) ფაილში `MODULE.bazel`, მიამაგრეთ კომიტი, რომლის გამოყენებაც გსურთ:

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

ეს იზიარებს სერთიფიკატებს Tuist CLI-თან და Gradle პლაგინთან; არსებული შესვლაც მუშაობს. CI-ზე გამოიყენეთ `TUIST_TOKEN` ან გაუშვით შესვლის სამიზნე Tuist-ის <.localized_link href="/guides/integrations/continuous-integration">OIDC ავთენტიკაციით</.localized_link>. არასოდეს მოათავსოთ სერთიფიკატები BUILD ფაილებში ან წესების ატრიბუტებში. გადაეცით `-- --url https://tuist.example.com` საკუთარ ჰოსტინგზე განთავსებულ ეგზემპლარში შესასვლელად.

ჩატვირთეთ მხოლოდ ის ადაპტერი, რომელიც გჭირდებათ თქვენს `BUILD.bazel` ფაილში:

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

შესრულებადი პრივიუ მოიცავს სამიზნის მიერ დეკლარირებულ runtime ფაილებს. განაცხადეთ ბიბლიოთეკები და რესურსები, რომლებიც თქვენს ინსტრუმენტს სჭირდება მის Bazel სამიზნეში და გამოიყენეთ გზები, რომლებიც მუშაობენ ბილდის დირექტორიის გარეთ.

## აგება და გამოქვეყნება

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

ჩაანაცვლეთ აპლიკაციისა და სიმულატორის პლატფორმის ლეიბლები თქვენი საკუთარი ლეიბლებით. გადაეცით `--url` საკუთარ ჰოსტინგზე განთავსებული Tuist წყაროსთვის და `--revision` Git კომიტთან ასოცირებისთვის.

გადაეცით `--publish --project account/project` წარმატებული ბილდის გასაზიარებლად. `--publish`-ის გარეშე, ან `--no-publish`-ით, არაფერი აიტვირთება და შესვლა არ არის საჭირო. ჩვეულებრივი `bazel build` არასოდეს აქვეყნებს, მათ შორის ქეშის გამოყენების შემთხვევაშიც. `tuist bazel setup` ააქტიურებს ქეშირებას და ინსაიტებს, მაგრამ არა გამოქვეყნებას.

## მხარდაჭერილი შედეგები

- **Android:** ხელმოწერილი აპლიკაციის APK-ები, დებაგ ბილდების ჩათვლით. დააინსტალირეთ Android SDK build-tools და ბრძანების ხაზის ინსტრუმენტები და დააყენეთ `ANDROID_HOME` ან `ANDROID_SDK_ROOT`. ტესტის APK-ები და Android App Bundles მხარდაჭერილი არ არის.
- **Apple:** ad-hoc-ით ხელმოწერილი სიმულატორისა და macOS აპლიკაციები, აგებული და ვერიფიცირებული macOS-ზე. ფიზიკურ მოწყობილობაზე ბილდები, ფრეიმვორქები, გაფართოებები და ტესტები მხარდაჭერილი არ არის. გამოიყენეთ archive შედეგი ექსპერიმენტული tree archives-ის ნაცვლად.
- **ბრძანების ხაზის ინსტრუმენტები:** macOS ან Linux შესრულებადი ფაილები arm64 ან x86_64 არქიტექტურისთვის, უნივერსალური macOS ბინარების ჩათვლით. სკრიპტებს სჭირდებათ shebang და ინტერპრეტატორი მიმღების სისტემაზე. განაცხადეთ runtime დამოკიდებულებები თქვენს სამიზნეში; Tuist არ აყენებს დაკარგულ ბიბლიოთეკებს ან ენის runtime-ებს.

## ქეშის გამეორება, შეცდომები და შენახვა

იგივე გამოქვეყნების გამეორება ხელახლა იყენებს არსებულ პრივიუს მის ხელახლა ატვირთვის გარეშე, მაშინაც კი, თუ Bazel აღადგენს ბილდს ქეშიდან. შედეგის, ტრეკის ან რევიზიის ცვლილება ქმნის ახალ გამოქვეყნებას. ატვირთვის შეცდომა აფერხებს ბრძანებას; შეგიძლიათ ხელახლა გაუშვათ იმის შესამოწმებლად, დასრულდა თუ არა გამოქვეყნება ხელახლა ცდამდე.

ბრძანება აკავშირებს თქვენი პროექტის პრივიუებთან, სადაც დამუშავებას შეიძლება გარკვეული დრო დასჭირდეს. პრივიუები იყენებენ პროექტის ნაგულისხმევ ხილვადობას.

არტეფაქტების გამოქვეყნებები იწურება 30 დღის შემდეგ ჰოსტინგზე განთავსებულ Tuist-ზე. საკუთარ ჰოსტინგზე განთავსებული ეგზემპლარები იყენებენ `TUIST_APP_PREVIEW_RETENTION_DAYS`; მისი დაუყენებლობა თიშავს ვადას ამ ოჯახისთვის. ვადაგასული გამოქვეყნების ჩანაწერების აღდგენა იგივე მოქმედების გამეორებით შეუძლებელია.

იხილეთ <.localized_link href="/guides/features/previews#run-a-preview">პრივიუს გაშვება</.localized_link> გამოქვეყნებული ბილდების გასაშვებად, წვდომისთვის, ტრეკებისა და README ბეჯებისთვის.

## Apple პრივიუები

Apple სიმულატორისა და macOS პრივიუებისთვის იხილეთ <.localized_link href="/guides/features/previews/run/macos">Tuist macOS კომპანიონის აპლიკაციის ინსტრუქციები</.localized_link>. ეს არ ცვლის Bazel-ის აპლიკაციის შესაბამისობის ან ხელმოწერის მოთხოვნებს.

## დაკავშირებული სამუშაო ნაკადები {#publish-from-once}

არსებულ Once ინტეგრაციებს აქვთ ცალკეული <.localized_link href="/guides/features/previews/once">არტეფაქტების გამოქვეყნების სახელმძღვანელო</.localized_link>. ორივე სამუშაო ნაკადი ინარჩუნებს გამოქვეყნებას ცალკე ქეშირებული გრაფის შესრულებისგან.
