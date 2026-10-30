---
{
  "title": "CLI",
  "titleTemplate": ":title · კოდი · კონტრიბუტორები · Tuist",
  "description": "შეიტანეთ წვლილი Tuist CLI-ში."
}
---
# CLI {#cli}

წყარო: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) და [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## რისთვის არის {#what-it-is-for}

CLI არის Tuist-ის გული. ის მართავს პროექტების გენერაციას, ავტომატიზაციის სამუშაო ნაკადებს (ტესტი, გაშვება, გრაფიკა და ინსპექცია) და უზრუნველყოფს ინტერფეისს Tuist სერვერთან ისეთი ფუნქციებისთვის, როგორიცაა ავთენტიკაცია, ქეში, ინსაითები, პრივიუები, რეესტრი და შერჩევითი ტესტირება.

## როგორ შეიტანოთ წვლილი {#how-to-contribute}

### მოთხოვნები {#requirements}

- macOS 14.0+
- Xcode 26+

### ლოკალურად მომზადება {#set-up-locally}

- კლონირება რეპოზიტორიის: `git clone git@github.com:tuist/tuist.git`
- დააინსტალირეთ Mise [მათი ოფიციალური ინსტალაციის სკრიპტის](https://mise.jdx.dev/getting-started.html) გამოყენებით (არა Homebrew) და გაუშვით `mise install`
- დააინსტალირეთ Tuist-ის დამოკიდებულებები: `tuist install`
- გენერირება სამუშაო სივრცის: `tuist generate`

გენერირებული პროექტი ავტომატურად იხსნება. თუ მოგვიანებით ხელახლა გახსნა დაგჭირდებათ, გაუშვით `open Tuist.xcworkspace`.

> [!NOTE]
> **Xed .**
>
> თუ ცდილობთ პროექტის გახსნას `xed .`-ის გამოყენებით, ის გახსნის პაკეტს და არა Tuist-ით გენერირებულ სამუშაო სივრცეს. გამოიყენეთ `Tuist.xcworkspace`.


### Tuist-ის გაშვება {#run-tuist}

#### Xcode-დან {#from-xcode}

ჩაასწორეთ `tuist` სქემა და დააყენეთ არგუმენტები, მაგალითად `generate --no-open`. დააყენეთ სამუშაო დირექტორია პროექტის ძირში (ან გამოიყენეთ `--path`).

> [!WARNING]
> **Projectdescription-ის კომპილაცია**
>
> CLI დამოკიდებულია `ProjectDescription`-ის აგებაზე. თუ გაშვება ვერ ხერხდება, ჯერ ააგეთ `Tuist-Workspace` სქემა.


#### ტერმინალიდან {#from-the-terminal}

ჯერ გააგენერირეთ სამუშაო სივრცე:

```bash
tuist generate --no-open
```

შემდეგ ააგეთ `tuist` შესრულებადი ფაილი Xcode-ით და გაუშვით DerivedData-დან:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

ან Swift Package Manager-ის მეშვეობით:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
