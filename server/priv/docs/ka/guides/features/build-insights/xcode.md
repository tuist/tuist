---
{
  "title": "Xcode-ის ბილდის ანალიტიკა",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "თვალი ადევნეთ Xcode-ის ბილდის ანალიტიკას Tuist-ის დაფაზე, რათა მონიტორინგი გაუწიოთ ლოკალური და CI ბილდების წარმადობას."
}
---
# Xcode-ის ბილდის ანალიტიკა {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იგივე კოდის მრავალჯერად ხელახლა კომპილაციას. Tuist Build Insights საშუალებას გაძლევთ თვალყური ადევნოთ ბილდის ანალიტიკას, რათა ტენდენციები გამოავლინოთ სანამ ლოკალური და CI ბილდების დრო შეზღუდვად გადაიქცევა.

ბილდის ანალიტიკა ეფუძნება `tuist inspect build` ბრძანებას, რომელიც ჩვეულებრივ ემატება სქემის post-action-ს.

ლოკალური ბილდების დროის თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება მისი სქემის post-action-ში დამატებით:

![Post-action ბილდების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> "Provide build settings from" ველი მიანიჭეთ შესრულებად ფაილს ან თქვენს ძირითად ბილდის სამიზნეს (target), რათა დაიჭიროთ ბილდის კონფიგურაცია.

> [!NOTE]
> post-scheme action არ სრულდება, როცა ბილდი ვერ ხერხდება.
>
> ამ შემთხვევაში მისი შესრულება შეგიძლიათ `runPostActionsOnFailure`-ის მნიშვნელობად `YES`-ის მითითებით სქემის `.xcscheme` ფაილის `<BuildAction>` ელემენტზე:
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
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური გზა. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ბილდის პარამეტრები უნდა იყოს მემკვიდრეობით მიღებული target-დან, რათა `mise` შეძლოს გაშვება `$SRCROOT`-დან.

[Homebrew](https://brew.sh/)-ისთვის, დაამატეთ Homebrew-ის გზები post-action გარემოში:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

შესვლის შემდეგ, ლოკალური ბილდები იწერება და ხელმისაწვდომია Tuist-ის დაშბორდიდან:

> [!TIP]
> დაშბორდზე სწრაფი წვდომისთვის, გაუშვით `tuist project show --web` CLI-დან.

![დაშბორდი ბილდის ანალიტიკით](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
