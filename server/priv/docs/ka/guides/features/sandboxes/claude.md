---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით Claude Managed Agents სესიები და Claude Code ღრუბლოვანი სესიები (claude.ai, დესკტოპისა და მობილური აპლიკაციები და claude --cloud) Tuist Sandboxes-ზე, Linux-სა ან macOS-ზე."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Sandboxes, როგორც Linux-ზე, ასევე macOS-ზე, ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა მიიღოთ წვდომა თქვენს ანგარიშზე.

Anthropic უშვებს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ის Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">sandbox-ს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist უშვებს იმ workers-ებსა და runners-ებს, რომლებიც ამ გარემოებს სჭირდებათ, ამიტომ თქვენ არაფერს მასპინძლობთ.

არსებობს გარემოების ორი ტიპი, თითოეული Claude-ის პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც თქვენ უშვებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. თქვენ ქმნით გარემოს (`env_…`) [Claude Console-ში](https://platform.claude.com/environments) და თითოეულ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები უშვებენ claude.ai-დან, Claude-ის desktop და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team-ის ან Enterprise Owner-ი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორის პარამეტრებში, თითოეული პლატფორმისთვის ერთს, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს გარემოს არჩევით.

ორივე მათგანი მიერთებულია Tuist API-ის მეშვეობით ანგარიშის ადმინისტრატორის მიერ. გაიარეთ ავტორიზაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს მიერთება {#managed-agents-connect}

მიერთება თქვენი ანგარიშის **Settings → Integrations → Claude** განყოფილებიდან. ფორმა ითხოვს თვითმასპინძელ გარემოს და იმ სარწმუნოებებს, რომლითაც Tuist უშვებს თავის სესიებს:

1. **შექმენით გარემო.** Claude Console-ში შექმენით თვითმასპინძელი გარემო [Environments](https://platform.claude.com/environments) გვერდზე, გახსენით ის და დააჭირეთ **Generate environment key**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ სარწმუნოება** ფორმის ზედა ნაწილში მდებარე სელექტორით (იხილეთ ქვემოთ).
3. **ჩასვით გარემოს ID და გასაღები** და აირჩიეთ გარემოს sandbox-ების პლატფორმა და კონფიგურაცია.

Tuist ინახავს გარემოს სარწმუნოებით მანამ, სანამ რაიმეს შეინახავს, ამიტომ არასწორი სარწმუნოება, ID ან workspace გამოიწვევს შეცდომას ფორმაში. ის ინახავს გასაღებებს დაშიფრულად და აღარასდროს აჩვენებს მათ. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების შესახებ იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ნაგულისხმები და sandbox-ების გამოსაცდელად ყველაზე სწრაფი გზა. ჩასვით API გასაღები დეველოპერის როლით გარემოს workspace-ში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც იყენებენ API გასაღებს; სანამ მას დაეყრდნობოდეთ, ნაცვლად ამისა, მიუერთეთ ის ფედერირებული იდენტობით, რათა Tuist-მა არ შეინახოს ხანგრძლივი ვადის გასაღები.

#### ფედერირებული იდენტობით {#managed-agents-connect-federated}

Tuist ავტორიზაციას გადის Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ის მეშვეობით, ამიტომ თქვენ არასდროს აწვდით მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ ადმინისტრატორის როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის გამომცემლის URL-ს და subject-ის პრეფიქსს. Claude Console-ში გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` scope-ით. დაამატეთ სამსახურის ანგარიში, რომელსაც ოსტატი ქმნის, გარემოს workspace-ში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **Settings → Organization** განყოფილებაში, ხოლო workspace-ის ID — **Settings → Workspaces** განყოფილებაში. Connect workload აჩვენებს სამსახურის ანგარიშისა და ფედერაციის წესის ID-ებს დასრულებისას, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის ტოკენს, Console-ის [ავტორიზაციის ისტორია](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ით {#managed-agents-connect-api}

ავტომატიზაციიდან მიერთებისთვის, შექმენით თვითმასპინძელი გარემო [Claude Console-ში](https://platform.claude.com/environments), შექმენით მისი გასაღები და გაუგზავნეთ ორივე Tuist-ს:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ით სესიების დასაწყებად, ასევე გაუგზავნეთ ან ოთხი ფედერაციის ID (იხილეთ [მიერთება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო ეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი sandbox-ების კონფიგურაციას, ხოლო `xcode_version` — მისი macOS sandbox-ების [Xcode](#xcode)-ს.

### სესიის დაწყება {#managed-agents-sessions}

ყოველი სესია ეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ ითხოვს.

**Claude API-ით**, შექმენით სესია ჩვეულებრივად გარემოს ID-ით და დააყენეთ `tuist_platform` სესიის მეტამონაცემებში `macos` ან `linux` მნიშვნელობად:

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, დააკლონოს საჯარო რეპოზიტორია sandbox-ში აგენტის პირველ ბრუნვამდე.

**Tuist-ის agent-sessions API-ით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და კლონავს პირად GitHub რეპოზიტორიებს, რომლებიც მიერთებულია თქვენს Tuist ანგარიშთან:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

როდესაც ანგარიშს ერთზე მეტი გარემო აქვს, გადასცეთ `agent_environment_id`. შეგიძლიათ დააკვირდეთ სესიას `GET /agent-sessions/{id}/events`-ით, უპასუხოთ `POST /agent-sessions/{id}/messages`-ით და დაასრულოთ ის `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორია იშლება `/workspace` დირექტორიაში Linux-ზე და `/Users/runner/work` დირექტორიაში macOS-ზე. სესიის sandbox იჩერდება აგენტის ბრუნვის დასრულების შემდეგ და განახლდება შემდეგი შეტყობინებისას.

### აირჩიეთ სესიის Xcode {#managed-agents-xcode}

სესიის Mac იტვირთება მანამ, სანამ Claude რაიმე ინსტრუმენტს გაუშვებს, ამიტომ Claude ვერ ირჩევს საკუთარ Xcode-ს. ვინც ქმნის სესიას, ის ირჩევს მას, ისევე როგორც macOS-ს. Tuist იყენებს პირველს ამ ჩამონათვალიდან, რომელიც დაყენებულია:

1. `xcode_version` Tuist-ის agent-sessions API-ში, `platform`-ის გვერდით. ვერსია, რომელსაც Tuist არ სთავაზობს, უარყოფილი იქნება სესიის შექმნისას, თქვენთვის ხელმისაწვდომი ვერსიების სიით.
2. `tuist_xcode_version` სესიის მეტამონაცემებში, როდესაც სესიას Claude API-ით ქმნით:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. გარემოს `xcode_version`, როდესაც სესია ეშვება გარემოს პლატფორმაზე.
4. ნაგულისხმევი Xcode.

Xcode პლატფორმის გარეშე ითხოვს macOS-ს. რამდენიმე რამ, რაც უნდა იცოდეთ:

- **სესია ინარჩუნებს თავის Xcode-ს.** მისი sandbox ერთხელ იტვირთება და მოგვიანებით შეტყობინება ან შეცვლილი მეტამონაცემები მას არ ცვლის. სხვა Xcode-ისთვის გამოიყენეთ ახალი სესია.
- **Tuist ამოწმებს მეტამონაცემებს, როდესაც პირველი ბრუნვა მოდის.** თუ `tuist_xcode_version` მიუთითებს Xcode-ზე, რომელსაც Tuist არ სთავაზობს, Tuist აჩერებს იმ ბრუნვას sandbox-ის გაშვების გარეშე და აღრიცხავს ვერსიებს, რომელთა არჩევაც შეგიძლიათ. გამოიყენეთ Tuist-ის agent-sessions API, რათა მიიღოთ შეცდომა სესიის შექმნისას.
- **macOS გარემოში Tuist ელოდება, ნაცვლად იმისა, რომ ივარაუდოს.** თუ Tuist ვერ კითხულობს ახალი სესიის მეტამონაცემებს, ის აჩერებს ბრუნვას და ცდილობს ხელახლა, ნაცვლად გარემოს Xcode-ის ჩატვირთვისა.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია სესიების შექმნა Claude workspace-ში, რომელიც ფლობს გარემოს, შეუძლია სესიების გაშვება თქვენს Tuist ანგარიშზე და მოითხოვოს macOS და მისი Xcode სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა ამ workspace-ზე.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფა (dashboard) ამას თქვენთვის აწყობს. API-ის საშუალებით, Tuist იგივე პრინციპით მუშაობს: ყოველ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და ხელს აწერს მოკლევადიან ტოკენს Anthropic-ის თითოეული გამოძახებისთვის, რომელსაც ის ცვლის Anthropic-ის რამდენიმე წუთით მოქმედ წვდომის ტოკენზე. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აწერს.

- ყოველი აგენტის გარემოს პასუხი შეიცავს `federation_issuer_url`-ს და `federation_subject`-ს (`account:123:agent-environment:456`). Console-ის Custom OIDC ოსტატში გამოიყენეთ გამომცემლის URL და ან ზუსტად ეს სუბიექტი, რათა დაუშვათ მხოლოდ ეს გარემო, ან `account:123:*` ანგარიშის ყველა გარემოს დასაშვებად. დაფის (dashboard) შემოწმებები იყენებენ სუბიექტს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოუპი `workspace:developer`.
- გაგზავნეთ ორგანიზაციის, workspace-ის, სერვისის ანგარიშის და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ით. როდესაც გარემოს აქვს როგორც ID-ები, ასევე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით 443 პორტზე საჯარო ჰოსტნეიმიდან. თუ თქვენი self-hosted Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო Console-ში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი სთავაზობს `<issuer>/jwks.json`-ზე. ჩასვით ის ხელახლა ყოველ ჯერზე, როდესაც Tuist-ის ხელმოწერის გასაღები იცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, როდესაც ის დაყენებული არ არის, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ის, რასაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია მისი გარემოს მიხედვით, ამიტომ თქვენ აკავშირებთ ერთ გარემოს თითოეული პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავე გვერდზე შექმენით self-hosted გარემო თითოეული პლატფორმისთვის, იმ სახელით, რომელსაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. დააკავშირეთ თითოეული გარემო თქვენს Tuist ანგარიშთან `kind`-ით, დაყენებული `claude_code`-ზე და მისი პლატფორმით:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   გაიმეორეთ `"platform": "linux"`-ით და მეორე გარემოს ID-ით და გასაღებით.

ერთი წუთის განმავლობაში გარემოები მზად არიან სესიების მიღებისთვის. უმოქმედო სესია ინარჩუნებს თავის sandbox-ს გაშვებულს 30 წუთის განმავლობაში, შემდეგ კი აჩერებს მას; სესიის შემდეგი შეტყობინება აღადგენს იმავე sandbox-ს. შეცვალეთ ლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### აირჩიეთ Linux ან macOS {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც ღრუბლოვან სესიას იწყებენ:

- **claude.ai, დესკტოპ და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ ეშვება მასზე. ერთი სესიისთვის რომ აირჩიოთ, გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას ჩვეულებრივად, და მათი sandbox-ები ითვლება თქვენს Tuist ანგარიშზე.

### აირჩიეთ Xcode {#xcode}

ყოველი macOS გარემო ტვირთავს ერთ <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>-ს, ნაგულისხმევს, თუ არ დააკავშირებთ მას `xcode_version`-ით, მაგალითად `"xcode_version": "26.1.1"`. ერთზე მეტის შესათავაზებლად, დააკავშირეთ გარემო თითოეულისთვის და დაარქვით მათ სახელი მის მიხედვით, მაგალითად **Tuist macOS · Xcode 26.1.1**. დეველოპერები შემდეგ ირჩევენ Xcode-ს გარემოს არჩევით.

გარემოს სხვა Xcode-ზე გადასაყვანად, განაახლეთ ის:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

ახალი სესიები იღებენ ახალ Xcode-ს, ხოლო სესიებს, რომლებსაც უკვე აქვთ sandbox, რჩებათ თავისი. `null` ბრუნდება ნაგულისხმევზე. იგივე ეხება Managed Agents გარემოებს, რომელთა სესიებსაც ასევე შეუძლიათ [აირჩიონ საკუთარი](#managed-agents-xcode).

### სესიების უფრო სწრაფი გაშვება და ბილდები {#claude-code-caching}

- **Tuist ქეში:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს ქეში იმავე რაკში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და `tuist_ex` Mix ამოცანები სესიაში თავისთავად შედიან სესიის იდენტობის ტოკენით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავთენტიკაციის სახელმძღვანელოში.
- **ქეშირებული checkouts:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია სესიის რეპოზიტორიის წაკითხვა, ახალი სესია იწყება იმავე ქეშირებული checkout-დან, რომელსაც თქვენი Tuist რანერები იყენებენ, ამიტომ ის იღებს მხოლოდ იმ კომიტებს, რომლებიც აკლია, ნაცვლად კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმევი შტოს უახლესი კომიტის ობიექტებს, რაც ქეშირებულ checkout-ს აქტუალურს ტოვებს მაშინაც კი, რეპოზიტორიებისთვის, რომლებიც არ აწარმოებენ CI-ს Tuist-ზე. მას ანახლებს მხოლოდ კომიტი, რომელსაც GitHub აცხობს ნაგულისხმევი შტოსთვის; სესიის საკუთარი შტოები არასდროს. გამორთეთ sandboxes ან წაშალეთ აპლიკაცია ამის შესაჩერებლად.
- **macOS:** Mac-ი იზიარებს Claude Code-ის ბილდის სესიებს, რომლებიც ეშვება თითოეულ VM-თან, ამიტომ ახალი სესია არ ჩამოტვირთავს მას.

## გამოიყენეთ Mac ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code სესიები, რომლებიც ეშვებიან Linux-ზე, როგორიცაა ღრუბლოვანი სესიები Anthropic-ის მიერ დაჰოსტებულ გარემოში, მაინც შეუძლიათ ააწყონ და შეამოწმონ Apple-პლატფორმის კოდი Tuist macOS sandbox-ზე, როგორც აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. განსხვავებით **Tuist macOS** გარემოსგან, სესია ინარჩუნებს თავის საკუთარ გარემოს.

**Tuist Linux** გარემოში არაფრის დაყენებაა საჭირო: Tuist CLI და Tuist MCP სერვერი უკვე დაყენებულია და შედის სესიის იდენტობით.

ღრუბლოვანი სესიებისთვის Anthropic-ის მიერ დაჰოსტებულ გარემოში:

1. გახადეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP სერვერი</.localized_link> ხელმისაწვდომი სესიებისთვის: დაამატეთ `https://tuist.dev/mcp` როგორც კონექტორი claude.ai-ში და ჩართეთ ის სესიისთვის, ან გამოაცხადეთ ის რეპოზიტორიის კომიტირებულ `.mcp.json`-ში.
2. დააინსტალირეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს ამ გარემოს, შეუძლია მისი წაკითხვა, ამიტომ არ მიანიჭოთ სხვა სკოპი, თუ მათ ასევე არ შეუძლიათ თქვენი კეშის გამოყენება: Mac-ის ბრძანებები იღებენ <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>-ს მხოლოდ იმ ფარგლებში, რაც ტოკენს აქვს, ამიტომ დაამატეთ `ci`, რათა Mac-ზე ბილდებმა შეძლონ თქვენი კეშის წაკითხვა და ჩაწერა.
4. მიეცით გარემოს Tuist-თან წვდომა. Anthropic-ის ნაგულისხმევი **Trusted** ქსელური წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, შეინარჩუნეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI ტვირთავს სესიის ფაილებს Mac-ზე `tuist.dev`-ის მეშვეობით, ამიტომ სხვა დომენი არ სჭირდება.

პირველი სინქრონიზაციის შემდეგ, Claude ასრულებს `mise install`-ს Mac-ზე რეპოზიტორიის ძირში, რათა დააინსტალიროს პროექტის მიერ მიმაგრებული Tuist; Tuist 4.218.0 და უფრო გვიანი ვერსიები შემდეგ თავად შედიან თქვენი ანგარიშის კეშში ყოველ ბრძანებაში.

Claude შლის Mac-ს, როდესაც დავალება დასრულდება. დარჩენილი Mac იწყებს პაუზას უმოქმედობისას და იშლება 14 დღიანი პაუზის შემდეგ. ამ გზით შექმნილი Mac-ები ითვლება თქვენს Tuist ანგარიშში, როგორც ნებისმიერი სხვა sandbox.
