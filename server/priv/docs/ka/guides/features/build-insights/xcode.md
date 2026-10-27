---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode-ის აგების ინსაიტები {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იგივე კოდის ხელახლა აგებას. Tuist Build Insights საშუალებას გაძლევთ თვალყური ადევნოთ აგების ანალიტიკას, რათა გამოავლინოთ ტენდენციები სანამ ლოკალური და CI აგების დროები ბოთლneckად იქცევა.

აგების ინსაიტებს მართავს `tuist inspect build` ბრძანება, რომელიც ჩვეულებრივ ემატება თქვენი სქემის post-action-ს.

ლოკალური აგების დროების თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება მისი თქვენი სქემის post-action-ში დამატებით:

![Post-action აგებების შესწავლისთვის](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> დააყენეთ ველი „Provide build settings from“ executable-ზე ან თქვენს ძირითად აგების სამიზნეზე, რათა დაიჭიროთ აგების კონფიგურაცია.


> [!NOTE]
> post-scheme action არ სრულდება, როდესაც აგება ვერხერხდება.

>
> ამ შემთხვევაში შეგიძლიათ მისი შესრულება `runPostActionsOnFailure`-ის `YES`-ზე დაყენებით შესაბამის `project.pbxproj` `BuildAction`-ში:
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
> **Mise-ის გზის ამოხსნა**
>
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური გზა. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. აგების პარამეტრები უნდა გადაეცემოდეს სამიზნიდან, რათა `mise` შეძლოს `$SRCROOT`-დან გაშვება.

[Homebrew](https://brew.sh/)-ისთვის, დაამატეთ Homebrew-ის გზები post-action გარემოში:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims ნაგულისხმევად გამორთულია. სქემის post-action-ისთვის ერთის კონფიგურაციისთვის, დააყენეთ `TUIST_ACTOR_ID` ამ სკრიპტში shell export-ებზე დაყრდნობის ნაცვლად. Dock-დან გაშვებული Xcode არ იღებს ცვლადებს `~/.zshrc`-დან. Homebrew-ით კონფიგურირებული claim-ის ცალსახად ჩასახშობად, გამოიყენეთ:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Mise-თან, გადაფარეთ მნიშვნელობა Mise-ის გარემოს ჩატვირთვის შემდეგ:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

გამოიყენეთ ცალსახა ლეიბლი ცარიელი მნიშვნელობის ნაცვლად opt-in-ისთვის.

შესვლის შემდეგ, ლოკალური აგებები თვალყურს ედევნება და ხელმისაწვდომია Tuist dashboard-იდან:

> [!TIP]
> dashboard-ზე სწრაფი წვდომისთვის, გაუშვით `tuist project show --web` CLI-დან.


![Dashboard აგების ინსაიტებით](/images/guides/features/build-insights/builds-dashboard.png)

## აგების ინსაიტები CI-ში {#continuous-integration}

CI-ზე აგების ინსაიტების თვალყურის დევნისთვის, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">ავტორიზებული</.localized_link>.

Xcodebuild-ით მართული CI-ისთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> `xcodebuild` actions-ის გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებას.

`-resultBundlePath`-ის გარეშე, საჭირო activity logs და result bundles არ გენერირდება და `tuist inspect build` ვერ აანალიზებს აგებას.

## Credential-free reporting კერძო ქსელში {#network-trusted-publishing}

self-hosted განლაგებას შეუძლია საშუალება მისცეს დეველოპერებს გამოაქვეყნონ დასრულებული ანგარიშები შესვლის გარეშე. ოპერატორმა უნდა დააკონფიგურიროს `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` ინსტანციაზე და გადატვირთოს ის, როგორც აღწერილია <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">self-hosting guide</.localized_link>-ში. ეს ვრცელდება ყველა მხარდაჭერილ პროექტზე; არ არსებობს dashboard პარამეტრი. დააკონფიგურირეთ self-hosted URL და პროექტი გარემოში, რომელსაც იყენებს თქვენი სქემის post-action ან ტერმინალი. CLI ავტომატურად აღმოაჩენს ინსტანციის პოლიტიკას, როდესაც credentials არ არის:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

ნამდვილად არარსებული credentials-ით, activity logs და XCResult bundles იპარსება ლოკალურად და იგზავნება სტრუქტურირებული ანგარიშების სახით. არ იგზავნება raw archive, attachment, coverage/history upload, remote processor, shard reference ან selective-execution evidence. ანგარიშები რჩება ხილული, მაგრამ ვერ აახლებს ავტორიზებული testcase მდგომარეობას ან ვერ მართავს quarantine/failure automations. Dashboards, cache და სხვა ავტორიზებული ბრძანებები კვლავ მოითხოვენ შესვლას. დატოვეთ ნებისმიერი cache ინტეგრაცია გამორთული, თუ credentials არ არის მიწოდებული.

არსებული credentials რჩება ავტორიზებული. არასწორი, დაზიანებული, ცარიელი ან უარყოფილი-refresh credentials ფეილდება და რჩება დისკზე, ასე რომ მოგვიანებითი ბრძანებები არ ხდებიან ჩუმად unsigned. ხელახლა შედით ან ცალსახად გამოდით, როგორც განზრახული აღდგენის მოქმედება. განაახლეთ ყველა server replica discovery-capable ვერსიამდე credential-free clients-ის განახლებამდე და დააკონფიგურირეთ საბოლოო server URL redirects-ის გარეშე. უფრო ძველ servers-ებს discovery-ს გარეშე, გამორთულ instances-ებს და discovery failures-ს კვლავ სჭირდებათ ავტორიზაცია. client-side opt-in არ არის საჭირო. დააყენეთ `TUIST_ACTOR_ID=""` დამოუკიდებლად, რათა გამოტოვოთ კონფიგურირებული actor claim; verified credential identity უცვლელი რჩება.

## Machine metrics {#machine-metrics}

აგების ინსაიტებმა შეიძლება შეიცავდეს machine-level performance metrics (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც იჭერება აგების დროს. ამის ჩასართავად, დააყენეთ მსუბუქი background daemon, რომელიც უწყვეტად იღებს სისტემის metrics:

```bash
tuist setup insights
```

ეს აწარმოებს ლოკალურ daemon-ს, რომელიც იღებს metrics ფონზე. მონაცემებს ავტომატურად იღებს `tuist inspect build` და ატვირთავს აგების ანგარიშთან ერთად.

> [!TIP]
> **Ci**
>
> გაუშვით `tuist setup insights` თქვენს CI მანქანებზე აგებამდე, რათა ასევე დაიჭიროთ machine metrics იქ.

machine metrics-ის შეგროვების შეწყვეტისთვის, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს daemon-ის LaunchAgent-ს, აშორებს მის plist-ს და შლის შეგროვებულ metrics და daemon logs `~/.local/state`-დან, ასე რომ ფონზე არაფერი რჩება გაშვებული.


## Report actor claim {#report-actor-claim}

Report-creation requests შეიცავს optional `x-tuist-actor-id` header-ს მხოლოდ მაშინ, როდესაც ცალსახად აყენებთ `TUIST_ACTOR_ID` organization-scoped label-ზე, მაგალითად `TUIST_ACTOR_ID=employee-123 tuist inspect build`. ლეიბლი ნაგულისხმევად არ იგზავნება და Tuist არ აღმოაჩენს operating-system usernames. ცარიელი `TUIST_ACTOR_ID` გამოტოვებს report-ში მითითებულ identifier-ს, მაგრამ არ აშორებს credential-based verified identity. Identifiers უნდა იყოს 1–128 bytes non-space printable ASCII; არასწორი overrides გამოიტოვება fallback-ის გარეშე. თუ custom proxy უარყოფს უცნობ headers-ებს, opt out გააკეთეთ ცარიელი environment override-ით.

Verified individual credentials აქვს უპირატესობა; client-reported identifiers სხვა შემთხვევაში ჩანს როგორც **Unverified** და არასდროს ანიჭებს უფლებებს ან არ აკავშირებს ავტომატურად მომხმარებლებთან. Identifiers ხილულია ყველასთვის, ვისაც შეუძლია ნახოს პროექტის ანგარიშები, მათ შორის public viewers, როდესაც პროექტი საჯაროა, და შედის data exports-ში, ამიტომ არ შეიტანოთ secrets. ეს ვრცელდება build, test და command-event ანგარიშებზე. ძველი servers იგნორირებს optional header-ს და ახალი servers იღებს ძველ clients-ებს მის გარეშე. ახალი shared-token ანგარიშები identifier-ის გარეშე აჩვენებენ **Unknown**-ს, გამომქვეყნებელი ორგანიზაციის ნაცვლად; ისტორიული ანგარიშები ინარჩუნებენ წინა attribution-ს. Build და test listings არჩევენ verified users-ს unverified reported identifiers-გან. ავტორიზაცია კვლავ საჭიროა, თუ self-hosted instance ცალსახად არ ჩართავს credential-free reporting-ს და client არ აღმოაჩენს ამ პოლიტიკას.

## Custom metadata {#custom-metadata}

შეგიძლიათ მიამაგროთ metadata აგებებს environment variables-ით filtering-ის გასაუმჯობესებლად.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | რამდენიმე ტეგი ერთ ცვლადში. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | გასაღები-მნიშვნელობის წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს shell-ში build-ის გამოძახებამდე:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
