---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode-ის აგების ინსაიტები {#xcode-build-insights}

დიდ პროექტებზე მუშაობა არ უნდა მოითხოვდეს ერთი და იმავე კოდის ხელახლა აგებას. Tuist Build Insights საშუალებას გაძლევთ თვალი ადევნოთ აგების ანალიტიკას, რათა გამოავლინოთ ტენდენციები სანამ ლოკალური და CI აგების დრო ბოთლneck-ად გადაიქცევა.

აგების ინსაიტებს მართავს `tuist inspect build` ბრძანება, რომელიც ჩვეულებრივ ემატება თქვენი სქემის post-action-ს.

ლოკალური აგების დროის თვალყურის დევნის დასაწყებად, შეგიძლიათ გამოიყენოთ `tuist inspect build` ბრძანება, დაამატეთ ის თქვენი სქემის post-action-ში:

![Post-action აგების შესამოწმებლად](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> დააყენეთ ველი "Provide build settings from" შესრულებად ფაილზე ან თქვენს ძირითად აგების სამიზნეზე, რათა დაიჭიროთ აგების კონფიგურაცია.


> [!NOTE]
> post-scheme action არ სრულდება, როდესაც აგება ვერ ხერხდება.

>
> ამ შემთხვევაში შეგიძლიათ შეასრულოთ ის, დააყენოთ `runPostActionsOnFailure` მნიშვნელობაზე `YES` შესაბამის `project.pbxproj` `BuildAction`-ში:
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
> **Mise ბილიკის გარჩევა**
>
> თქვენი გარემოს `PATH` არ გადაეცემა სქემის post action-ს, ამიტომ გამოიყენეთ Mise-ის აბსოლუტური ბილიკი. ეს დამოკიდებულია იმაზე, თუ როგორ დააინსტალირეთ Mise. აგების პარამეტრები უნდა გადაეცემოდეს სამიზნიდან, რათა `mise` შეძლოს გაშვება `$SRCROOT`-დან.

[Homebrew](https://brew.sh/)-ისთვის, დაამატეთ Homebrew-ის ბილიკები post-action გარემოში:

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

Mise-ით, გადაფარეთ მნიშვნელობა Mise-ის გარემოს ჩატვირთვის შემდეგ:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

გამოიყენეთ ცალსახა ლეიბლი ცარიელი მნიშვნელობის ნაცვლად opt-in-ისთვის.

შესვლის შემდეგ, ლოკალური აგებები თვალყურს ედევნება და ხელმისაწვდომია Tuist dashboard-დან:

> [!TIP]
> dashboard-თან სწრაფი წვდომისთვის, გაუშვით `tuist project show --web` CLI-დან.


![Dashboard აგების ინსაიტებით](/images/guides/features/build-insights/builds-dashboard.png)

## აგების ინსაიტები CI-ში {#continuous-integration}

CI-ზე აგების ინსაიტების თვალყურის დევნისთვის, დარწმუნდით, რომ CI არის <.localized_link href="/guides/integrations/continuous-integration#authentication">აუთენტიფიცირებული</.localized_link>.

Xcodebuild-ით მართული CI-ისთვის საჭიროა:
- გამოიყენეთ <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> `xcodebuild` actions-ის გამოძახებისას.
- დაამატეთ `-resultBundlePath` თქვენს `xcodebuild` ბრძანებას.

`-resultBundlePath`-ის გარეშე, საჭირო activity logs და result bundles არ გენერირდება და `tuist inspect build` ვერ აანალიზებს აგებას.

## Credential-free რეპორტინგი კერძო ქსელში {#network-trusted-publishing}

self-hosted განლაგებას შეუძლია დაუშვას დეველოპერებმა გამოაქვეყნონ დასრულებული რეპორტები შესვლის გარეშე. ოპერატორმა უნდა დააკონფიგურიროს `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` ინსტანციაზე და გადატვირთოს ის, როგორც აღწერილია <.localized_link href="/guides/server/self-host/server#network-trusted-access">self-hosting guide</.localized_link>-ში. ეს ვრცელდება ყველა მხარდაჭერილ პროექტზე; dashboard-ში პარამეტრი არ არსებობს. დააკონფიგურირეთ self-hosted URL და პროექტი გარემოში, რომელსაც იყენებს თქვენი სქემის post-action ან ტერმინალი. CLI ავტომატურად აღმოაჩენს ინსტანციის პოლიტიკას, როდესაც credentials არ არის:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

ნამდვილად არარსებული credentials-ით, activity logs და XCResult bundles იპარსება ლოკალურად და იგზავნება სტრუქტურირებული რეპორტების სახით. raw archive, attachment, coverage/history upload, remote processor, shard reference ან selective-execution evidence არ იგზავნება. რეპორტები რჩება ხილული, მაგრამ ვერ აახლებენ აუთენტიფიცირებული testcase state-ს ან არ ამუშავებენ quarantine/failure automations-ს. Dashboards და სხვა привилეგიური ბრძანებები კვლავ მოითხოვენ შესვლას. შეინახეთ cache integration გამორთული, თუ ინსტანცია ცალკე არ ააქტიურებს network-trusted cache access-ს ან credentials არ არის მოწოდებული.

არსებული credentials რჩება აუთენტიფიცირებული. არასწორი, დაზიანებული, ცარიელი ან rejected-refresh credentials იხურება და რჩება დისკზე, ასე რომ მოგვიანებით ბრძანებები არ ხდება ჩუმად unsigned. ხელახლა შედით ან ცალსახად გამოდით, როგორც განზრახული აღდგენის მოქმედება. განაახლეთ ყველა server replica discovery-capable ვერსიამდე credential-free clients-ის განახლებამდე და დააკონფიგურირეთ საბოლოო server URL redirects-ის გარეშე. უფრო ძველი servers discovery-ს გარეშე, გამორთული instances და discovery failures კვლავ მოითხოვენ აუთენტიფიკაციას. client-side opt-in არ არის საჭირო. დააყენეთ `TUIST_ACTOR_ID=""` დამოუკიდებლად, რათა გამოტოვოთ კონფიგურირებული actor claim; verified credential identity უცვლელი რჩება.

## Machine metrics {#machine-metrics}

აგების ინსაიტებმა შეიძლება მოიცვას machine-level performance metrics (CPU, მეხსიერება, ქსელი და დისკის გამოყენება), რომლებიც იჭერება აგების დროს. ამის ჩასართავად, დააყენეთ მსუბუქი background daemon, რომელიც უწყვეტად იღებს სისტემის metrics-ს:

```bash
tuist setup insights
```

ეს უშვებს ლოკალურ daemon-ს, რომელიც იღებს metrics-ს ფონურად. მონაცემები ავტომატურად იღებს `tuist inspect build` და იტვირთება აგების რეპორტთან ერთად.

> [!TIP]
> **Ci**
>
> გაუშვით `tuist setup insights` თქვენს CI მანქანებზე აგებამდე, რათა ასევე დაიჭიროთ machine metrics იქ.

machine metrics-ის შეგროვების შესაჩერებლად, გაუშვით:

```bash
tuist teardown insights
```

ეს ტვირთავს daemon-ის LaunchAgent-ს, აშორებს მის plist-ს და შლის შეგროვებულ metrics-ს და daemon logs-ს `~/.local/state`-დან, ასე რომ ფონში არაფერი რჩება გაშვებული.


## Report actor claim {#report-actor-claim}

რეპორტის შექმნის მოთხოვნები შეიცავს optional `x-tuist-actor-id` header-ს მხოლოდ მაშინ, როდესაც ცალსახად აყენებთ `TUIST_ACTOR_ID` organization-scoped ლეიბლზე, მაგალითად `TUIST_ACTOR_ID=employee-123 tuist inspect build`. ლეიბლი ნაგულისხმევად არ იგზავნება და Tuist არ ადგენს operating-system username-ს. ცარიელი `TUIST_ACTOR_ID` გამოტოვებს reported identifier-ს, მაგრამ არ აშორებს credential-based verified identity-ს. Identifiers უნდა იყოს 1–128 ბაიტი non-space printable ASCII; არასწორი overrides გამოტოვებულია fallback-ის გარეშე. თუ custom proxy უარყოფს უცნობ headers-ს, opt out ცარიელი environment override-ით.

Verified individual credentials აქვთ უპირატესობა; client-reported identifiers წარმოდგენილია როგორც **Unverified** და არასდროს ანიჭებენ ნებართვებს ან არ აკავშირებენ ავტომატურად მომხმარებლებთან. Identifiers ხილულია ყველასთვის, ვისაც შეუძლია ნახოს პროექტის რეპორტები, მათ შორის public viewers, როდესაც პროექტი საჯაროა, და შედის data exports-ში, ამიტომ არ შეიტანოთ secrets. ეს ვრცელდება აგების, ტესტის და command-event რეპორტებზე. ძველი servers იგნორირებენ optional header-ს და ახალი servers იღებენ ძველ clients-ს მის გარეშე. ახალი shared-token რეპორტები identifier-ის გარეშე აჩვენებენ **Unknown**, publishing organization-ის ნაცვლად; ისტორიულ რეპორტებს ინარჩუნებენ წინა attribution-ს. აგების და ტესტის სიები განასხვავებენ verified users-ს unverified reported identifiers-გან. აუთენტიფიკაცია რჩება საჭირო, თუ self-hosted instance ცალსახად არ ააქტიურებს credential-free reporting-ს და client აღმოაჩენს ამ პოლიტიკას.

## Custom metadata {#custom-metadata}

შეგიძლიათ აგებებს მიამაგროთ მეტამონაცემები გარემოს ცვლადების საშუალებით, რათა გაუმჯობესდეთ ფილტრაცია.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | რამდენიმე ტეგი ერთ ცვლადში. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | გასაღები-მნიშვნელობის წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს shell-ში აგების გამოძახებამდე:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
