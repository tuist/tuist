---
{
  "title": "Xcode ბილდის ანალიტიკა",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "თვალყური ადევნეთ Xcode ბილდების ანალიტიკას Tuist-ის დაშბორდზე, რათა მონიტორინგი გაუწიოთ ლოკალური და CI ბილდების შესრულებას."
}
---
# Xcode-ის ბილდის ანალიტიკა {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იგივე კოდის ხელახლა კომპილაციას. Tuist Build Insights საშუალებას გაძლევთ თვალი ადევნოთ ბილდის ანალიტიკას, რათა გამოავლინოთ ტენდენციები, სანამ ლოკალური და CI ბილდების დრო შეფერხების მიზეზად იქცევა.

ბილდის ანალიტიკა ემყარება `tuist inspect build` ბრძანებას, რომელიც ჩვეულებრივ ემატება თქვენი სქემის post-action-ს.

ლოკალური ბილდების დროის თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება მისი თქვენი სქემის post-action-ში დამატებით:

![Post-action ბილდების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> "Provide build settings from" ველი დააყენეთ შესრულებად ფაილზე ან თქვენს ძირითად ბილდის სამიზნეზე (target), რათა დაიჭიროთ ბილდის კონფიგურაცია.

> [!NOTE]
> post-scheme action არ სრულდება, როცა ბილდი ვერ ხერხდება.
>
> ამ შემთხვევაში მისი შესრულება შეგიძლიათ `runPostActionsOnFailure`-ის `YES`-ზე დაყენებით სქემის `.xcscheme` ფაილის `<BuildAction>` ელემენტში:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/)-ისთვის, გაააქტიურეთ `tuist` post-action გარემოში:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise-ის გზის გარჩევა**
>
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური გზა. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ბილდის პარამეტრები უნდა გადაეცემოდეს სამიზნიდან (target), რათა `mise` შეძლოს გაშვება `$SRCROOT`-დან.

[Homebrew](https://brew.sh/)-ისთვის, დაამატეთ Homebrew-ის გზები post-action გარემოში:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

შესვლის შემდეგ, ლოკალური ბილდები ითვალისწინება და ხელმისაწვდომია Tuist-ის დაშბორდიდან:

> [!TIP]
> დაშბორდთან სწრაფი წვდომისთვის, გაუშვით `tuist project show --web` CLI-დან.

![დაშბორდი ბილდის ანალიტიკით](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
