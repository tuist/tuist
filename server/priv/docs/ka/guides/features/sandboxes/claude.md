---
{
  "title": "Claude",
  "titleTemplate": ":title · სენდბოქსები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით Claude Managed Agents-ის სესიები და Claude Code-ის ღრუბლოვანი სესიები (claude.ai, დესკტოპისა და მობილური აპლიკაციები და claude --cloud) Tuist Sandboxes-ზე, Linux-სა ან macOS-ზე."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Sandboxes, როგორც Linux-ზე, ასევე macOS-ზე, ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა მიიღოთ წვდომა თქვენს ანგარიშზე.

Anthropic მართავს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ის Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">სენდბოქსს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist აწარმოებს იმ სამუშაო პროცესებსა და გამშვებებს (runners), რაც ამ გარემოებს სჭირდება, ამიტომ თქვენ არაფერი უნდა განათავსოთ საკუთარ სერვერებზე.

არსებობს გარემოს ორი ტიპი, თითო Claude-ის თითოეული პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. თქვენ ქმნით გარემოს (`env_…`) [Claude Console-ში](https://platform.claude.com/environments) და თითოეულ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის დესკტოპისა და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team-ის ან Enterprise-ის მფლობელი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორის პარამეტრებში, თითოეული პლატფორმისთვის ერთს, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს შესაბამისი გარემოს შერჩევით.

ორივე ტიპი კავშირდება Tuist API-ს მეშვეობით ანგარიშის ადმინისტრატორის მიერ. გაიარეთ ავტორიზაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

დაუკავშირდით თქვენი ანგარიშის **Settings → Integrations → Claude** განყოფილებიდან. ფორმა ითხოვს თვითმასპინძელ გარემოს და იმ სერთიფიკატს (credential), რომლითაც Tuist იწყებს სესიებს:

1. **შექმენით გარემო.** Claude Console-ში, შექმენით თვითმასპინძელი გარემო [Environments](https://platform.claude.com/environments) გვერდზე, გახსენით ის და დააჭირეთ **Generate environment key**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ სერთიფიკატი** ფორმის ზედა ნაწილში მდებარე სელექტორის გამოყენებით (იხილეთ ქვემოთ).
3. **ჩააკოპირეთ გარემოს ID და გასაღები** და აირჩიეთ გარემოს სენდბოქსების პლატფორმა და კონფიგურაცია (shape).

Tuist იღებს გარემოს სერთიფიკატით რაიმეს შენახვამდე, ამიტომ არასწორი სერთიფიკატი, ID ან სამუშაო სივრცე (workspace) ფორმაში შეცდომას გამოიწვევს. ის ინახავს გასაღებებს დაშიფრულად და მათ აღარასდროს აჩვენებს. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების (shapes) სანახავად იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ნაგულისხმები და სენდბოქსების გამოსაცდელად ყველაზე სწრაფი გზა. ჩააკოპირეთ API გასაღები დეველოპერის როლით გარემოს სამუშაო სივრცეში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც იყენებენ API გასაღებს; სანამ მას დაეყრდნობოდეთ, უმჯობესია დააკავშიროთ ის ფედერირებული იდენტობით, რათა Tuist-მა არ შეინახოს ხანგრძლივი ვადის გასაღები.

#### ფედერირებული იდენტობით {#managed-agents-connect-federated}

Tuist ავტორიზდება Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ის მეშვეობით, ამიტომ თქვენ არასდროს აწვდით მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ ადმინისტრატორის როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის გამომცემის URL-ს და subject-ის პრეფიქსს. Claude Console-ში, გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` სკოუპით. დაამატეთ ვიზარდის მიერ შექმნილი სერვისის ანგარიში გარემოს სამუშაო სივრცეში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **Settings → Organization** ქვეშ, ხოლო სამუშაო სივრცის ID — **Settings → Workspaces** ქვეშ. Connect workload აჩვენებს სერვისის ანგარიშისა და ფედერაციის წესის ID-ებს დასრულებისას, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის ტოკენს, Console-ის [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ს მეშვეობით {#managed-agents-connect-api}

ავტომატიზაციიდან დასაკავშირებლად, შექმენით თვითმასპინძელი გარემო [Claude Console-ში](https://platform.claude.com/environments), შექმენით მისი გასაღები და გაგზავნეთ ორივე Tuist-ზე:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ს მეშვეობით სესიების დასაწყებად, ასევე გაგზავნეთ ან ოთხი ფედერაციის ID (იხილეთ [დაკავშირება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო ეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`-ს; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი სენდბოქსების კონფიგურაციას, ხოლო `xcode_version` — მისი macOS სენდბოქსების [Xcode](#xcode)-ს.

### სესიის დაწყება {#managed-agents-sessions}

თითოეული სესია ეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ ითხოვს.

**Claude API-ს მეშვეობით**, შექმენით სესია ჩვეულებრივად გარემოს ID-ით და დააყენეთ `tuist_platform` სესიის მეტამონაცემებში `macos` ან `linux` მნიშვნელობად:

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

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, დააკლონოს საჯარო რეპოზიტორია სენდბოქსში აგენტის პირველ ბრუნვამდე.

**Tuist-ის agent-sessions API-ს მეშვეობით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და კლონავს კერძო GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

როდესაც ანგარიშს ერთზე მეტი გარემო აქვს, გადასცეთ `agent_environment_id`. შეგიძლიათ მიჰყვეთ სესიას `GET /agent-sessions/{id}/events`-ით, უპასუხოთ `POST /agent-sessions/{id}/messages`-ით და დაასრულოთ ის `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორია იღება `/workspace`-ში Linux-ზე და `/Users/runner/work`-ში macOS-ზე. სესიის სენდბოქსი ჩერდება აგენტის ბრუნვის დასრულების შემდეგ და განახლდება შემდეგ შეტყობინებაზე.

### აირჩიეთ სესიის Xcode {#managed-agents-xcode}

სესიის Mac იტვირთება სანამ Claude რაიმე ინსტრუმენტს გაუშვებს, ამიტომ Claude ვერ ირჩევს საკუთარ Xcode-ს. ვინც ქმნის სესიას, ის ირჩევს მას, ისევე როგორც macOS-ს. Tuist იყენებს პირველს ამ ჩამონათვალიდან, რომელიც დაყენებულია:

1. `xcode_version` Tuist-ის agent-sessions API-ში, `platform`-ის გვერდით. ვერსია, რომელსაც Tuist არ სთავაზობს, უარყოფილი იქნება სესიის შექმნისას, თქვენთვის ხელმისაწვდომი ვერსიების სიით.
2. `tuist_xcode_version` სესიის მეტამონაცემებში, როდესაც სესიას ქმნით Claude API-ით:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. გარემოს `xcode_version`, როდესაც სესია ეშვება გარემოს პლატფორმაზე.
4. ნაგულისხმები Xcode.

Xcode პლატფორმის გარეშე ითხოვს macOS-ს. რამდენიმე რამ, რაც უნდა იცოდეთ:

- **სესია ინარჩუნებს თავის Xcode-ს.** მისი სენდბოქსი ერთხელ იტვირთება და მოგვიანებით შეტყობინება ან შეცვლილი მეტამონაცემები არ ცვლის მას. გამოიყენეთ ახალი სესია სხვა Xcode-სთვის.
- **Tuist ამოწმებს მეტამონაცემებს, როდესაც პირველი ბრუნვა მოდის.** თუ `tuist_xcode_version` ასახელებს Xcode-ს, რომელსაც Tuist არ სთავაზობს, Tuist აჩერებს იმ ბრუნვას სენდბოქსის გაშვების გარეშე და აღრიცხავს ვერსიებს, რომელთა არჩევაც შეგიძლიათ. გამოიყენეთ Tuist-ის agent-sessions API შეცდომის მისაღებად სესიის შექმნისას.
- **macOS გარემოში Tuist ელოდება, ნაცვლად იმისა, რომ ივარაუდოს.** თუ Tuist ვერ კითხულობს ახალი სესიის მეტამონაცემებს, ის აჩერებს ბრუნვას და ცდილობს ხელახლა, ნაცვლად გარემოს Xcode-ის ჩატვირთვისა.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია სესიების შექმნა Claude სამუშაო სივრცეში, რომელიც ფლობს გარემოს, შეუძლია სესიების გაშვება თქვენს Tuist ანგარიშზე და მოითხოვოს macOS და მისი Xcode სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა ამ სამუშაო სივრცეზე.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფა ამას თქვენთვის აწყობს. API-ს საშუალებით, Tuist იგივე პრინციპით მუშაობს: ყოველ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და ხელს აწერს მოკლე ვადის ტოკენს Anthropic-ის თითოეული გამოძახებისთვის, რომელსაც ის ცვლის Anthropic-ის წვდომის ტოკენზე, რომელიც რამდენიმე წუთს ძლებს. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აწერს.

- ყოველი აგენტის გარემოს პასუხი შეიცავს `federation_issuer_url`-ს და `federation_subject`-ს (`account:123:agent-environment:456`). კონსოლის Custom OIDC ოსტატში, გამოიყენეთ გამომცემლის URL და ან ზუსტად ეს სუბიექტი, მხოლოდ ამ გარემოს დასაშვებად, ან `account:123:*` ანგარიშის ყველა გარემოს დასაშვებად. დაფის დაყენების შემოწმებები იყენებენ სუბიექტს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოპი `workspace:developer`.
- გააგზავნეთ ორგანიზაციის, სამუშაო სივრცის, სერვისის ანგარიშის და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ით. როდესაც გარემოს აქვს როგორც ID-ები, ასევე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით 443 პორტზე საჯარო ჰოსტნეიმიდან. თუ თქვენი self-hosted Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო კონსოლში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი აწვდის `<issuer>/jwks.json`-ზე. ჩასვით ის ხელახლა ყოველ ჯერზე, როდესაც Tuist-ის ხელმოწერის გასაღები იცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, როდესაც ის დაყენებული არ არის, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ისინი, რომლებსაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია მისი გარემოს მიხედვით, ამიტომ თქვენ აკავშირებთ ერთ გარემოს ყოველი პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრირების გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმვე გვერდზე, შექმენით self-hosted გარემო ყოველი პლატფორმისთვის, იმ სახელით, რომელსაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. დააკავშირეთ თითოეული გარემო თქვენს Tuist ანგარიშთან, `kind` დაყენებული `claude_code`-ზე და მის პლატფორმაზე:

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

   გაიმეორეთ `"platform": "linux"`-ით და სხვა გარემოს ID-ით და გასაღებით.

ერთი წუთის განმავლობაში, გარემოები მზად არიან სესიების მიღებისთვის. უმოქმედო სესია ინარჩუნებს თავის სენდბოქსს გაშვებულს 30 წუთის განმავლობაში, შემდეგ კი აჩერებს მას; სესიის შემდეგი შეტყობინება აღადგენს იმავე სენდბოქსს. შეცვალეთ ლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### აირჩიეთ Linux ან macOS {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც იწყებენ ღრუბლოვან სესიას:

- **claude.ai, დესკტოპ და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ მასზე გაეშვება. ერთი სესიისთვის რომ აირჩიოთ, გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას ჩვეულებრივად, და მათი სენდბოქსები ითვლება თქვენს Tuist ანგარიშზე.

### აირჩიეთ Xcode {#xcode}

ყოველი macOS გარემო ტვირთავს ერთ <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>-ს, ნაგულისხმევს, თუ არ დააკავშირებთ მას `xcode_version`-ით, მაგალითად `"xcode_version": "26.1.1"`. ერთზე მეტის შესათავაზებლად, დააკავშირეთ გარემო თითოეულისთვის და დაარქვით მათ სახელი მის მიხედვით, მაგალითად **Tuist macOS · Xcode 26.1.1**. დეველოპერები შემდეგ ირჩევენ Xcode-ს გარემოს არჩევით.

გარემოს სხვა Xcode-ზე გადასაყვანად, განაახლეთ ის:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

ახალი სესიები იღებენ ახალ Xcode-ს, ხოლო სესიებს, რომლებსაც უკვე აქვთ სენდბოქსი, ინარჩუნებენ თავისას. `null` ბრუნდება ნაგულისხმევზე. იგივე ეხება Managed Agents გარემოებს, რომელთა სესიებსაც ასევე შეუძლიათ [აირჩიონ საკუთარი](#managed-agents-xcode).

### სესიების უფრო სწრაფი გაშვება და ბილდები {#claude-code-caching}

- **Tuist ქეში:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს ქეში იმავე რაკში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და `tuist_ex` Mix ამოცანები სესიაში თავისთავად შედიან სესიის იდენტობის ტოკენით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავთენტიკაციის სახელმძღვანელოში.
- **ქეშირებული ჩექაუთები:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია წაიკითხოს სესიის რეპოზიტორია, ახალი სესია იწყება იმავე ქეშირებული ჩექაუთიდან, რომელსაც თქვენი Tuist რანერები იყენებენ, ამიტომ ის იღებს მხოლოდ იმ კომიტებს, რომლებიც აკლია, ნაცვლად კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმევი ბრენჩის უახლესი კომიტის ობიექტებს, რაც ქეშირებულ ჩექაუთს აქტუალურს ტოვებს მაშინაც კი, როდესაც რეპოზიტორიები არ აწარმოებენ CI-ს Tuist-ზე. მხოლოდ კომიტი, რომელსაც GitHub აცხადებს ნაგულისხმევი ბრენჩისთვის, ანახლებს მას; სესიის საკუთარი ბრენჩები არასდროს. გამორთეთ სენდბოქსები ან წაშალეთ აპლიკაცია ამის შესაჩერებლად.
- **macOS:** Mac-ი იზიარებს Claude Code-ის ბილდის სესიებს, რომლებიც გაეშვა თითოეულ VM-ზე, ამიტომ ახალი სესია არ ჩამოტვირთავს მას.

## გამოიყენეთ Mac ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code სესიები, რომლებიც Linux-ზე ეშვებიან, როგორიცაა ღრუბლოვანი სესიები Anthropic-ის მიერ დაფინანსებულ გარემოში, მაინც შეუძლიათ ააწყონ და შეამოწმონ Apple-პლატფორმის კოდი Tuist macOS სენდბოქსზე, როგორც აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. განსხვავებით **Tuist macOS** გარემოსგან, სესია ინარჩუნებს თავის საკუთარ გარემოს.

**Tuist Linux** გარემოში არაფერია დასაყენებელი: Tuist CLI და Tuist MCP სერვერი უკვე დაყენებულია და შედიან სესიის იდენტობით.

ღრუბლოვანი სესიებისთვის Anthropic-ის მიერ დაფინანსებულ გარემოში:

1. გახადეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP სერვერი</.localized_link> ხელმისაწვდომი სესიებისთვის: დაამატეთ `https://tuist.dev/mcp` როგორც კონექტორი claude.ai-ში და ჩართეთ ის სესიისთვის, ან გამოაცხადეთ ის რეპოზიტორიის კომიტირებულ `.mcp.json`-ში.
2. დააყენეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს ამ გარემოს, შეუძლია მისი წაკითხვა, ამიტომ არ მიანიჭოთ სხვა სკოპი, თუ მათ არ აქვთ თქვენი კეშის გამოყენების უფლება: Mac-ის ბრძანებები იღებენ <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>-ს მხოლოდ იმ ფარგლებში, რაც ტოკენს აქვს, ამიტომ დაამატეთ `ci` Mac-ზე ბილდებისთვის, რომ შეძლონ თქვენი კეშის წაკითხვა და ჩაწერა.
4. მიეცით გარემოს Tuist-თან წვდომა. Anthropic-ის ნაგულისხმევი **Trusted** ქსელური წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, შეინარჩუნეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI ტვირთავს სესიის ფაილებს Mac-ზე `tuist.dev`-ის საშუალებით, ამიტომ სხვა დომენი არ სჭირდება.

პირველი სინქრონიზაციის შემდეგ, Claude ასრულებს `mise install` Mac-ზე რეპოზიტორიის ძირითად დირექტორიაში პროექტისთვის მიმაგრებული Tuist-ის დასაყენებლად; Tuist 4.218.0 და მომდევნო ვერსიები შემდეგ თვითონ შედიან თქვენი ანგარიშის ქეშში ყოველ ბრძანებაში.

### მზა Mac-ები {#remote-mac-snapshots}

**Tuist Linux** გარემოს შეუძლია წინასწარ მოამზადოს ეს Mac-ები. დააყენეთ მისი macOS setup სკრიპტი API-ით (`macos_setup_script` on `PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`), მაგალითად:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

როდესაც Claude ქმნის Mac-ს რეპოზიტორიისთვის, რომელიც დაკავშირებულია თქვენს ერთ-ერთ Tuist პროექტთან, `create_sandbox` იღებს რეპოზიტორიას და Mac იტვირთება ამ რეპოზიტორიის სნეპშოტიდან მისი Xcode-სთვის: ნაგულისხმევი ბრენჩი კლონდება `~/work/<name>`-ში, სკრიპტი გაეშვა იქ და ბილდის პროდუქტები ადგილზეა. პირველი `tuist sandbox sync` აგზავნის მხოლოდ იმ ფაილებს, რომლებიც განსხვავდება ამ კომიტისგან, ამიტომ Xcode ხელახლა აწყობს მხოლოდ იმას, რაც შეიცვალა. რეპოზიტორიისა და Xcode-ს პირველი Mac იტვირთება ცარიელი და მისი სნეპშოტი აშენდება თავისუფალ Mac-ზე, ერთ საათამდე, შემდგომი Mac-ებისთვის. სკრიპტის, Xcode-ს ან გამოსახულების შეცვლა ხელახლა აშენებს მას.

Claude შლის Mac-ს, როდესაც დავალება დასრულდება. დარჩენილი Mac ჩერდება, როდესაც თავისუფალია და იშლება 14 დღის გაჩერების შემდეგ. ასე შექმნილი Mac-ები ითვლება თქვენს Tuist ანგარიშში, როგორც ნებისმიერი სხვა სენდბოქსი.
