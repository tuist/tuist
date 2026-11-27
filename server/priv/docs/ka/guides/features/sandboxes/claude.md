---
{
  "title": "Claude",
  "titleTemplate": ":title · სენდბოქსები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით Claude Managed Agents-ის სესიები და Claude Code-ის ღრუბლოვანი სესიები (claude.ai, დესკტოპისა და მობილური აპლიკაციები, და claude --cloud) Tuist-ის სენდბოქსებზე, Linux-ზე ან macOS-ზე."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **მხოლოდ მოწვევით**
>
> Tuist Sandboxes, როგორც Linux-ზე, ისე macOS-ზე, ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენს ანგარიშზე წვდომა მოითხოვოთ.

Anthropic მართავს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ერთ-ერთი Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">sandbox-ს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist უზრუნველყოფს ამ გარემოებისთვის საჭირო worker-ებსა და runner-ებს, ასე რომ, თქვენ არაფერს მასპინძლობთ.

არსებობს გარემოების ორი ტიპი, თითოეული Claude-ის პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. თქვენ ქმნით გარემოს (`env_…`) [Claude Console-ში](https://platform.claude.com/environments) და ყოველ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის desktop და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team ან Enterprise Owner ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორულ პარამეტრებში, თითოეული პლატფორმისთვის ერთს, ხოლო დეველოპერები ირჩევენ Linux ან macOS გარემოს შერჩევით.

ორივე ტიპი კავშირდება Tuist API-ის მეშვეობით ანგარიშის ადმინისტრატორის მიერ. გაიარეთ ავტორიზაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

დააკავშირეთ თქვენი ანგარიშის **Settings → Integrations → Claude** განყოფილებიდან. ფორმა ითხოვს თვითმასპინძელ გარემოს და credential-ს, რომლითაც Tuist იწყებს სესიებს:

1. **შექმენით გარემო.** Claude Console-ში, [Environments](https://platform.claude.com/environments) გვერდზე შექმენით თვითმასპინძელი გარემო, გახსენით ის და დააჭირეთ **Generate environment key**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ credential** ფორმის ზედა ნაწილში მდებარე სელექტორით (იხილეთ ქვემოთ).
3. **ჩასვით გარემოს ID და გასაღები** და აირჩიეთ გარემოს sandbox-ების პლატფორმა და კონფიგურაცია (shape).

Tuist ინახავს მონაცემების შენახვამდე იღებს გარემოს credential-ით, ამიტომ არასწორი credential, ID ან workspace გამოიწვევს შეცდომას ფორმაში. ის ინახავს გასაღებებს დაშიფრულად და აღარასდროს აჩვენებს მათ. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების (shapes) სანახავად იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ეს არის ნაგულისხმები და sandbox-ების გამოსაცდელად ყველაზე სწრაფი გზა. ჩასვით API გასაღები, რომელსაც აქვს developer როლი გარემოს workspace-ში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც იყენებენ API გასაღებს; სანამ ერთ-ერთს ენდობოდეთ, დააკავშირეთ ის federated identity-ით, რათა Tuist-მა არ შეინახოს ხანგრძლივი ვადის გასაღები.

#### Federated identity-ით {#managed-agents-connect-federated}

Tuist ავტორიზაციას გადის Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ის მეშვეობით, ამიტომ თქვენ არასდროს აწვდით მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ admin როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის issuer URL-სა და subject prefix-ს. Claude Console-ში გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` scope-ით. დაამატეთ wizard-ის მიერ შექმნილი service account გარემოს workspace-ში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **Settings → Organization** ქვეშ, ხოლო workspace ID — **Settings → Workspaces** ქვეშ. Connect workload დასრულებისას აჩვენებს service account-ისა და federation rule-ის ID-ებს, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის token-ს, Console-ის [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ით {#managed-agents-connect-api}

ავტომატიზაციიდან დასაკავშირებლად, შექმენით თვითმასპინძელი გარემო [Claude Console-ში](https://platform.claude.com/environments), შექმენით მისი გასაღები და გაუგზავნეთ ორივე Tuist-ს:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ით სესიების დასაწყებად, ასევე გაუგზავნეთ ან ოთხივე federation ID (იხილეთ [დაკავშირება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო გაეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`-ს; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი sandbox-ების კონფიგურაციას (shape), ხოლო `xcode_version` — მისი macOS sandbox-ების [Xcode](#xcode)-ს.

### სესიის დაწყება {#managed-agents-sessions}

ყოველი სესია გაეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ ითხოვს.

**Claude API-ით**, შექმენით სესია ჩვეულებრივად გარემოს ID-ით და დააყენეთ `tuist_platform` სესიის metadata-ში `macos` ან `linux` მნიშვნელობად:

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

`repository_url` და, სურვილისამებრ, `repository_ref` (branch ან commit) აიძულებს Tuist-ს, კლონიროს საჯარო რეპოზიტორია sandbox-ში აგენტის პირველ ბრუნვამდე.

**Tuist-ის agent-sessions API-ით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და კლონირებს კერძო GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

როდესაც ანგარიშს აქვს ერთზე მეტი გარემო, გადასცეთ `agent_environment_id`. სესიის თვალყურის დევნა შეგიძლიათ `GET /agent-sessions/{id}/events`-ით, პასუხის გაგზავნა `POST /agent-sessions/{id}/messages`-ით, ხოლო დასრულება `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორია იშლება `/workspace` დირექტორიაში Linux-ზე და `/Users/runner/work` დირექტორიაში macOS-ზე. სესიის sandbox იჩერდება აგენტის ბრუნვის დასრულების შემდეგ და განახლდება შემდეგი შეტყობინებისას.

### სესიის Xcode-ის არჩევა {#managed-agents-xcode}

სესიის Mac იტვირთება მანამ, სანამ Claude რაიმე ინსტრუმენტს გაუშვებს, ამიტომ Claude ვერ ირჩევს საკუთარ Xcode-ს. მას ირჩევს ის, ვინც ქმნის სესიას, ისევე, როგორც macOS-ს. Tuist იყენებს პირველს, რომელიც დაყენებულია:

1. `xcode_version` Tuist-ის agent-sessions API-ში, `platform`-ის გვერდით. ვერსია, რომელსაც Tuist არ სთავაზობს, უარყოფილი იქნება სესიის შექმნისას, თქვენთვის ხელმისაწვდომი ვერსიების სიით.
2. `tuist_xcode_version` სესიის metadata-ში, როდესაც სესიას ქმნით Claude API-ით:

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. გარემოს `xcode_version`, როდესაც სესია გაეშვება გარემოს პლატფორმაზე.
4. ნაგულისხმები Xcode.

Xcode პლატფორმის მითითების გარეშე ითხოვს macOS-ს. რამდენიმე რამ, რაც უნდა იცოდეთ:

- **სესია ინარჩუნებს თავის Xcode-ს.** მისი sandbox ერთხელ იტვირთება და მოგვიანებით შეტყობინება ან შეცვლილი metadata არ ცვლის მას. სხვა Xcode-ისთვის გამოიყენეთ ახალი სესია.
- **Tuist ამოწმებს metadata-ს, როდესაც პირველი ბრუნვა მოდის.** თუ `tuist_xcode_version` მიუთითებს Xcode-ზე, რომელსაც Tuist არ სთავაზობს, Tuist აჩერებს იმ ბრუნვას sandbox-ის გაშვების გარეშე და აღრიცხავს ვერსიებს, რომელთა არჩევაც შეგიძლიათ. გამოიყენეთ Tuist-ის agent-sessions API, რათა მიიღოთ შეცდომა სესიის შექმნისას.
- **macOS გარემოში Tuist ელოდება, ნაცვლად ვარაუდის.** თუ Tuist ვერ კითხულობს ახალი სესიის metadata-ს, ის აჩერებს ბრუნვას და ცდილობს ხელახლა, ნაცვლად გარემოს Xcode-ის ჩატვირთვის.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია შექმნას სესიები Claude workspace-ში, რომელიც ფლობს გარემოს, შეუძლია გაუშვას სესიები თქვენს Tuist ანგარიშზე და მოითხოვოს macOS და მისი Xcode სესიის metadata-ს მეშვეობით. შესაბამისად, შეზღუდეთ წვდომა იმ workspace-ზე.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფა (dashboard) ამას თქვენთვის აწყობს. API-ს მეშვეობით, Tuist იგივენაირად მუშაობს: ყოველ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და ხელს აწერს მოკლე ვადიან ტოკენს Anthropic-ის ყოველი გამოძახებისთვის, რომელსაც ის ცვლის Anthropic-ის წვდომის ტოკენზე, რომელიც რამდენიმე წუთს ძლებს. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აწერს.

- ყოველი აგენტის გარემოს პასუხი შეიცავს `federation_issuer_url`-ს და `federation_subject`-ს (`account:123:agent-environment:456`). Console-ის Custom OIDC ოსტატში, გამოიყენეთ გამომცემლის URL და ან ზუსტად ეს სუბიექტი, რათა დაუშვათ მხოლოდ ეს გარემო, ან `account:123:*`, რათა დაუშვათ ანგარიშის ყოველი გარემო. დაფის (dashboard) შემოწმებები იყენებენ სუბიექტს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოპი `workspace:developer`.
- გაგზავნეთ ორგანიზაციის, workspace-ის, სერვისის ანგარიშის და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ით. როდესაც გარემოს აქვს როგორც ID-ები, ასევე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით 443 პორტზე საჯარო ჰოსტნეიმიდან. თუ თქვენი self-hosted Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო Console-ში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი აწვდის `<issuer>/jwks.json`-ზე. ჩასვით ის ხელახლა ყოველ ჯერზე, როდესაც Tuist-ის ხელმოწერის გასაღები იცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, როდესაც ის დაყენებული არ არის, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code cloud სესიები არის ისინი, რომლებსაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude desktop და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია მისი გარემოს მიხედვით, ამიტომ თქვენ აკავშირებთ ერთ გარემოს ყოველი პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამას სჭირდება Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავე გვერდზე, შექმენით self-hosted გარემო ყოველი პლატფორმისთვის, იმ სახელით, რომელსაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ ყოველი გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. დააკავშირეთ ყოველი გარემო თქვენს Tuist ანგარიშთან `kind`-ით, დაყენებული `claude_code`-ზე და მის პლატფორმაზე:

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

ერთ წუთში, გარემოები მზად იქნება სესიების მიღებისთვის. უმოქმედო სესია ინარჩუნებს თავის sandbox-ს გაშვებულს 30 წუთის განმავლობაში, შემდეგ აჩერებს მას; სესიის შემდეგი შეტყობინება აღადგენს იმავე sandbox-ს. შეცვალეთ ლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### Linux-ის ან macOS-ის არჩევა {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც იწყებენ cloud სესიას:

- **claude.ai, desktop და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ ეშვება მასზე. ერთი სესიისთვის არჩევისას, გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმები გარემოს ID Claude Code [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code გამოყენებას, როგორც ჩვეულებრივ, და მათი sandboxes ითვლება თქვენს Tuist ანგარიშზე.

### Xcode-ის არჩევა {#xcode}

ყოველი macOS გარემო ტვირთავს ერთ <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>-ს, ნაგულისხმევს, თუ არ დააკავშირებთ მას `xcode_version`-ით, მაგალითად `"xcode_version": "26.1.1"`. ერთზე მეტის შესათავაზებლად, დააკავშირეთ გარემო ყოველისთვის და დაარქვით მათ სახელი მის მიხედვით, მაგალითად **Tuist macOS · Xcode 26.1.1**. დეველოპერები შემდეგ ირჩევენ Xcode-ს გარემოს არჩევით.

გარემოს სხვა Xcode-ზე გადასაყვანად, განაახლეთ ის:

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

ახალი სესიები იღებენ ახალ Xcode-ს, და სესიებს, რომლებსაც უკვე აქვთ sandbox, ინარჩუნებენ თავისას. `null` ბრუნდება ნაგულისხმევზე. იგივე ეხება Managed Agents გარემოებს, რომელთა სესიებსაც ასევე შეუძლიათ [აირჩიონ საკუთარი](#managed-agents-xcode).

### სესიების უფრო სწრაფი გაშვება და ბილდები {#claude-code-caching}

- **Tuist cache:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს cache იმავე rack-ში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და `tuist_ex` Mix tasks სესიაში თავისთავად შედიან სესიის identity token-ით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავტორიზაციის სახელმძღვანელოში.
- **Cached checkouts:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია წაიკითხოს სესიის რეპოზიტორია, ახალი სესია იწყება იმავე cached checkout-დან, რომელსაც თქვენი Tuist runners იყენებენ, ამიტომ ის იღებს მხოლოდ იმ კომიტებს, რომლებიც აკლია, ნაცვლად კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმები ბრენჩის უახლესი კომიტის ობიექტებს, რაც cached checkout-ს აქტუალურს ინარჩუნებს იმ რეპოზიტორიებისთვისაც, რომლებიც არ აწარმოებენ CI-ს Tuist-ზე. მხოლოდ კომიტი, რომელსაც GitHub აცხადებს ნაგულისხმები ბრენჩისთვის, ანახლებს მას; სესიის საკუთარი ბრენჩები არასდროს. გამორთეთ sandboxes ან წაშალეთ აპლიკაცია ამის შესაჩერებლად.
- **macOS:** Mac-ი იზიარებს Claude Code build სესიებს, რომლებიც გაეშვა თითოეულ VM-ზე, ამიტომ ახალი სესია არ ჩამოტვირთავს მას.

## Mac-ის გამოყენება ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code სესიები, რომლებიც ეშვებიან Linux-ზე, როგორიცაა cloud სესიები Anthropic-ის მიერ დაჰოსტებულ გარემოში, მაინც შეუძლიათ ააწყონ და დატესტონ Apple-პლატფორმის კოდი Tuist macOS sandbox-ზე, როგორც აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. განსხვავებით **Tuist macOS** გარემოსგან, სესია ინარჩუნებს თავის გარემოს.

**Tuist Linux** გარემოში არაფერია დასაყენებელი: Tuist CLI და Tuist MCP სერვერი უკვე დაყენებულია და შედიან სესიის identity-ით.

Anthropic-ის მიერ დაჰოსტებულ გარემოში cloud სესიებისთვის:

1. გახადეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> ხელმისაწვდომი სესიებისთვის: დაამატეთ `https://tuist.dev/mcp` როგორც connector claude.ai-ში და ჩართეთ ის სესიისთვის, ან გამოაცხადეთ ის რეპოზიტორიის commited `.mcp.json`-ში.
2. დააყენეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს ამ გარემოს, შეუძლია მისი წაკითხვა, ამიტომ არ მიანიჭოთ მას სხვა სკოპი, თუ მათ არ აქვთ თქვენი cache-ის გამოყენების უფლება: Mac-ის ბრძანებები იღებენ <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>-ს მხოლოდ იმ ფარგლებში, რაც ტოკენს აქვს, ამიტომ დაამატეთ `ci` Mac-ზე ბილდებისთვის, რათა მათ შეძლონ თქვენი cache-ის წაკითხვა და ჩაწერა.
4. მიეცით გარემოს Tuist-თან წვდომა. Anthropic-ის ნაგულისხმევი **Trusted** ქსელური წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, დატოვეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI ატვირთავს სესიის ფაილებს Mac-ზე `tuist.dev`-ის მეშვეობით, ამიტომ სხვა დომენი არ სჭირდება.

Mac-ს აქვს Tuist CLI და გაუშვებს პროექტის საკუთარ ვერსიას, როდესაც ის pinned-ია mise-ის მეშვეობით; Tuist 4.218.0 და მოგვიანებითი ვერსიები თვითონ შედიან თქვენი ანგარიშის cache-ში ყოველ ბრძანებაში.

### მზა Mac-ები {#remote-mac-snapshots}

**Tuist Linux** გარემოს შეუძლია წინასწარ მოამზადოს ეს Mac-ები. დააყენეთ მისი macOS setup script API-ის მეშვეობით (`macos_setup_script` on `PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}`), მაგალითად:

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

როდესაც Claude ქმნის Mac-ს რეპოზიტორიისთვის, რომელიც დაკავშირებულია თქვენს ერთ-ერთ Tuist პროექტთან, `create_sandbox` იღებს რეპოზიტორიას და Mac იტვირთება ამ რეპოზიტორიის snapshot-დან მისი Xcode-ისთვის: ნაგულისხმევი branch კლონირდება `~/work/<name>`-ში, სკრიპტი იქ გაეშვა და build პროდუქტები ადგილზეა. პირველი `tuist sandbox sync` აგზავნის მხოლოდ იმ ფაილებს, რომლებიც განსხვავდება ამ commit-ისგან, ამიტომ Xcode ხელახლა აწყობს მხოლოდ იმას, რაც შეიცვალა. რეპოზიტორიისა და Xcode-ის პირველი Mac იტვირთება ცარიელი და მისი snapshot აშენდება idle Mac-ზე, ერთ საათამდე, შემდგომი Mac-ებისთვის. სკრიპტის, Xcode-ის ან image-ის შეცვლა ხელახლა აშენებს მას. Snapshot ინარჩუნებს image-ის simulator-ებს და შლის იმას, რაც სკრიპტმა შექმნა, და თითოეული ასეთი Mac იწყებს image-ის უახლესი Pro iPhone-ის (iPhone 18 Pro Xcode 27.2-ზე) ჩატვირთვას მისი გაშვებისთანავე, ამიტომ ის მზად არის პირველი build-ის დასრულების დროისთვის; ააწყეთ ასევე ამ simulator-ისთვის სკრიპტში, რათა სესიის build-ებმა მისთვის ხელახლა გამოიყენონ snapshot-ის შედეგები.

Claude შლის Mac-ს, როდესაც დავალება დასრულდება. დარჩენილი Mac ჩერდება idle მდგომარეობაში და იშლება 14 დღის ჩერების შემდეგ. ასე შექმნილი Mac-ები ითვლებიან თქვენს Tuist ანგარიშში, როგორც ნებისმიერი სხვა sandbox.
