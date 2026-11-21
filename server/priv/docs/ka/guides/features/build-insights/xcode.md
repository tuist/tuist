---
{
  "title": "Xcode ბილდის ანალიტიკა",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "თვალყური ადევნეთ Xcode ბილდის ანალიტიკას Tuist-ის დაფაზე, რათა მონიტორინგი გაუწიოთ ლოკალური და CI ბილდების შესრულებას."
}
---
# Xcode-ის ბილდის ანალიტიკა {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იმავე კოდის ხელახლა კომპილაციას. Tuist Build Insights საშუალებას გაძლევთ თვალყური ადევნოთ ბილდის ანალიტიკას, რათა გამოავლინოთ ტენდენციები სანამ ლოკალური და CI ბილდის დროები „ბოთლის ყელად“ გადაიქცევა.

ბილდის ანალიტიკა ეფუძნება `tuist inspect build` ბრძანებას, რომელიც ჩვეულებრივ ემატება თქვენი სქემის post-action-ს.

ლოკალური ბილდის დროების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება მისი თქვენი სქემის post-action-ში დამატებით:

![Post-action ბილდების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> "Provide build settings from" ველი მიანიჭეთ შესრულებად ფაილს ან თქვენს ძირითად ბილდის სამიზნეს (target), რათა აღიბეჭდოს ბილდის კონფიგურაცია.

> [!NOTE]
> post-scheme action არ სრულდება, როცა ბილდი ვერხერხდება.
>
> ამ შემთხვევაში მისი შესრულება შეგიძლიათ `runPostActionsOnFailure`-ის `YES`-ზე დაყენებით სქემის `.xcscheme` ფაილის `<BuildAction>` ელემენტზე:
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
> **Mise-ის გზის ამოცნობა**
>
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური გზა. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ბილდის პარამეტრები უნდა გადაეცემოდეს სამიზნიდან (target), რათა `mise` შეძლოს `$SRCROOT`-დან გაშვება.

[Homebrew](https://brew.sh/)-ისთვის, დაამატეთ Homebrew-ის გზები post-action გარემოში:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

შესვლის შემდეგ, ლოკალური ბილდები იწერება და ხელმისაწვდომია Tuist-ის დაფაზე (dashboard):

> [!TIP]
> დაფაზე სწრაფი წვდომისთვის, გაუშვით `tuist project show --web` CLI-დან.

![დაფა ბილდის ანალიტიკით](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
