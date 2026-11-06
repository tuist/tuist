---
{
  "title": "Xcode ბილდის ანალიტიკა",
  "titleTemplate": ":title · ბილდის ანალიტიკა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "აკონტროლეთ Xcode-ის ბილდების ანალიტიკა Tuist-ის დაფაზე, რათა შეაფასოთ ლოკალური და CI ბილდების წარმადობა."
}
---
# Xcode-ის ბილდების ინსაიტები {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იმავე კოდის ხელახლა კომპილაციას. Tuist Build Insights საშუალებას გაძლევთ თვალყური ადევნოთ ბილდების ანალიტიკას, რათა ტენდენციები გამოავლინოთ სანამ ლოკალური და CI ბილდების დრო „ბოთლneck“-ად გადაიქცევა.

ბილდების ინსაიტებს ამუშავებს `tuist inspect build` ბრძანება, რომელიც ჩვეულებრივ ემატება სქემის post-action-ს.

ლოკალური ბილდების დროის თვალთვალის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება მისი სქემის post-action-ში დამატებით:

![Post-action ბილდების ინსპექტირებისთვის](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> „Provide build settings from“ ველი დააყენეთ შესრულებად ფაილზე ან თქვენს ძირითად ბილდის სამიზნეზე, რათა დაიჭიროთ ბილდის კონფიგურაცია.


> [!NOTE]
> post-scheme action არ სრულდება, როცა ბილდი ვერხერდება.

>
> ამ შემთხვევაში მისი შესრულება შეგიძლიათ `runPostActionsOnFailure`-ის `YES`-ზე დაყენებით შესაბამის `project.pbxproj` `BuildAction`-ში:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/)-ისთვის, post-action გარემოში გაააქტიურეთ `tuist`:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise-ის გზის გარჩევა**
>
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური გზა. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. ბილდის პარამეტრები უნდა გადაეცეს სამიზნიდან, რათა `mise` შეძლოს `$SRCROOT`-დან გაშვება.

[Homebrew](https://brew.sh/)-ისთვის, post-action გარემოში დაამატეთ Homebrew-ის გზები:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims ნაგულისხმევად გამორთულია. სქემის post-action-ისთვის ერთის კონფიგურაციისას, ამ სკრიპტში დააყენეთ `TUIST_ACTOR_ID` shell export-ებზე დაყრდნობის ნაცვლად. Dock-დან გაშვებული Xcode არ იღებს ცვლადებს `~/.zshrc`-დან. Homebrew-ით კონფიგურირებული claim-ის ცხადად ჩასახშობად, გამოიყენეთ:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Mise-ით, გადაწერეთ მნიშვნელობა Mise-ის გარემოს ჩატვირთვის შემდეგ:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

opt-in-ისთვის ცარიელი მნიშვნელობის ნაცვლად გამოიყენეთ ცხადი ლეიბლი.

შესვლის შემდეგ, ლოკალური ბილდები ითვალთვალება და ხელმისაწვდომია Tuist dashboard-იდან:

> [!TIP]
> dashboard-ზე სწრაფად წვდომისთვის, CLI-დან გაუშვით `tuist project show --web`.


![Dashboard ბილდების ინსაიტებით](/images/guides/features/build-insights/builds-dashboard.png)

## Build Insights CI-ში {#continuous-integration}

CI-ზე ბილდების ინსაიტების თვალთვალისთვის, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">.</.localized_link>

Xcodebuild-ით მართული CI-ისთვის საჭიროა:
- <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>-ის გამოყენება `xcodebuild` ქმედებების გამოძახებისას.
- `-resultBundlePath`-ის დამატება თქვენს `xcodebuild` ბრძანებაში.

`-resultBundlePath`-ის გარეშე, საჭირო activity logs და result bundles არ გენერირდება და `tuist inspect build` ვერ აანალიზებს ბილდს.

## Credential-free რეპორტინგი კერძო ქსელში {#network-trusted-publishing}

self-hosted განლაგება შეუძლია დეველოპერებს საშუალება მისცეს დაასრულებული რეპორტები გამოაქვეყნონ შესვლის გარეშე. ოპერატორმა უნდა დააკონფიგურიროს `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` ინსტანსზე და გადატვირთოს ის, როგორც აღწერილია <.localized_link href="/guides/server/self-host/server#network-trusted-access">-ში</.localized_link>. ეს ვრცელდება ყველა მხარდაჭერილ პროექტზე; dashboard-ის პარამეტრი არ არსებობს. დააკონფიგურეთ self-hosted URL და პროექტი იმ გარემოში, რომელსაც იყენებს თქვენი სქემის post-action ან ტერმინალი. CLI ავტომატურად აღმოაჩენს ინსტანსის პოლიტიკას, როცა credentials არ არის:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

ნამდვილად არარსებული credentials-ის შემთხვევაში, activity logs და XCResult bundles იპარსება ლოკალურად და იგზავნება სტრუქტურირებული რეპორტების სახით. არ იგზავნება raw archive, attachment, coverage/history upload, remote processor, shard reference ან selective-execution evidence. რეპორტები ხილული რჩება, მაგრამ ვერ აახლებს authenticated testcase state-ს და ვერ მართავს quarantine/failure automations-ს. Dashboards და სხვა привилეგირებული ბრძანებები კვლავ მოითხოვს შესვლას. cache integration დატოვეთ გამორთული, თუ ინსტანსი ცალკე არ ააქტიურებს network-trusted cache access-ს ან credentials არ არის მიწოდებული.

არსებული credentials რჩება authenticated. არასწორი, დაზიანებული, ცარიელი ან rejected-refresh credentials იხურება და რჩება დისკზე, რათა მომდევნო ბრძანებები უხმოოდ არ გახდეს unsigned. ხელახლა შედით ან ცხადად გამოდით, როგორც განზრახული აღდგენის ქმედება. credential-free კლიენტების განახლებამდე ყველა server replica განაახლეთ discovery-capable ვერსიამდე და დააკონფიგურეთ საბოლოო server URL გადამისამართებების გარეშე. ძველ სერვერებს discovery-ის გარეშე, გამორთულ ინსტანსებს და discovery-ის შეცდომებს კვლავ სჭირდებათ authentication. client-side opt-in არ არის საჭირო. `TUIST_ACTOR_ID=""` დამოუკიდებლად დააყენეთ, რათა გამოტოვოთ კონფიგურირებული actor claim; verified credential identity უცვლელი რჩება.

## Machine metrics {#machine-metrics}

ბილდების ინსაიტები შეიძლება მოიცავდეს machine-level performance metrics-ებს (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც იჭერება ბილდის დროს. ამის ჩასართავად, დააყენეთ მსუბუქი background daemon, რომელიც უწყვეტად იღებს სისტემის metrics-ებს:

```bash
tuist setup insights
```

ეს აწარმოებს ლოკალურ daemon-ს, რომელიც ფონურად იღებს metrics-ებს. მონაცემებს ავტომატურად იღებს `tuist inspect build` და ატვირთავს ბილდის რეპორტთან ერთად.

> [!TIP]
> **Ci**
>
> CI მანქანებზე ბილდამდე გაუშვით `tuist setup insights`, რათა იქაც დაიჭიროთ machine metrics.

machine metrics-ების შეგროვების შეწყვეტისთვის, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს daemon-ის LaunchAgent-ს, აშორებს მის plist-ს და შლის შეგროვებულ metrics-ებს და daemon logs-ს `~/.local/state`-დან, ასე რომ ფონურად არაფერი რჩება გაშვებული.


## Report actor claim {#report-actor-claim}

რეპორტის შექმნის მოთხოვნები მოიცავს optional `x-tuist-actor-id` header-ს მხოლოდ მაშინ, როცა ცხადად აყენებთ `TUIST_ACTOR_ID` organization-scoped ლეიბლზე, მაგალითად `TUIST_ACTOR_ID=employee-123 tuist inspect build`. ლეიბლი ნაგულისხმევად არ იგზავნება და Tuist არ აღმოაჩენს operating-system username-ს. ცარიელი `TUIST_ACTOR_ID` გამოტოვებს reported identifier-ს, მაგრამ არ აშორებს credential-based verified identity-ს. Identifiers უნდა იყოს 1–128 ბაიტი non-space printable ASCII; არასწორი overrides გამოტოვდება fallback-ის გარეშე. თუ custom proxy უარყოფს უცნობ headers-ებს, opt out გააკეთეთ ცარიელი environment override-ით.

დადასტურებულ ინდივიდუალურ სერთიფიკატებს აქვთ უპირატესობა; კლიენტის მიერ მოწოდებული იდენტიფიკატორები სხვა შემთხვევაში ჩანს, როგორც **დაუდასტურებელი** და არასდროს ანიჭებენ ნებართვებს ან ავტომატურად არ აკავშირებენ მომხმარებლებთან. იდენტიფიკატორები ხილულია ყველასთვის, ვისაც შეუძლია ნახოს პროექტის ანგარიშები, მათ შორის საჯარო მაყურებლებისთვის, როდესაც პროექტი საჯაროა, და შედის მონაცემთა ექსპორტში, ამიტომ არ ჩაწეროთ საიდუმლოებები. ეს ვრცელდება ბილდების, ტესტებისა და ბრძანებების მოვლენების ანგარიშებზე. ძველი სერვერები იგნორირებენ ოფციონალურ ჰედერს, ხოლო ახალი სერვერები იღებენ ძველ კლიენტებს მის გარეშე. ახალი გაზიარებული-ტოკენის ანგარიშები იდენტიფიკატორის გარეშე აჩვენებენ **უცნობია**-ს, გამომქვეყნებელი ორგანიზაციის ნაცვლად; ისტორიულ ანგარიშებს რჩებათ წინა ატრიბუცია. ბილდებისა და ტესტების სიები განასხვავებენ დადასტურებულ მომხმარებლებს დაუდასტურებელი მოწოდებული იდენტიფიკატორებისგან. ავტორიზაცია კვლავ საჭიროა, თუ თვითმასპინძლობად განლაგებული ინსტანსი ცალსახად არ ჩართავს სერთიფიკატების გარეშე ანგარიშგებას და კლიენტი არ აღმოაჩენს ამ პოლიტიკას.

## Custom metadata {#custom-metadata}

შეგიძლიათ ბილდებს დაურთოთ მეტამონაცემები გარემოს ცვლადების საშუალებით, რათა გაუმჯობესდეთ ფილტრაცია.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | რამდენიმე ტეგი ერთ ცვლადში. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | საკვანძო-მნიშვნელობის წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს შელში ბილდის გამოძახებამდე:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
