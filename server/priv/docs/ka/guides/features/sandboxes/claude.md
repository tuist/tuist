---
{
  "title": "Claude",
  "titleTemplate": ":title · სენდბოქსები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით Claude Managed Agents-ის სესიები და Claude Code-ის ღრუბლოვანი სესიები (claude.ai, დესკტოპისა და მობილურის აპლიკაციები და claude --cloud) Tuist-ის სენდბოქსებზე, Linux-ზე ან macOS-ზე."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **მხოლოდ მიწვევით**
>
> Tuist Sandboxes, როგორც Linux-ზე, ისე macOS-ზე, ამჟამად მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენი ანგარიშისთვის წვდომა მოითხოვოთ.

Anthropic მართავს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ერთ-ერთი Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">sandbox-ს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist აწარმოებს იმ სამუშაო პროცესებსა და გამშვებებს (runners), რომლებიც ამ გარემოებს სჭირდებათ, ასე რომ, თქვენ არაფრის განთავსება არ გიწევთ.

არსებობს გარემოების ორი ტიპი, თითოეული Claude-ის პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. თქვენ ქმნით გარემოს (`env_…`) [Claude Console-ში](https://platform.claude.com/environments) და თითოეულ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team-ის ან Enterprise-ის მფლობელი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორის პარამეტრებში, თითოეული პლატფორმისთვის ცალ-ცალკე, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს შესაბამისი გარემოს არჩევით.

ორივე ტიპი ანგარიშის ადმინისტრატორის მიერ Tuist API-ს მეშვეობით უკავშირდება. გაიარეთ ავტორიზაცია `tuist auth login`-ით, შემდეგ კი:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

დაუკავშირდით თქვენი ანგარიშის **Settings → Integrations → Claude** განყოფილებიდან. ფორმა ითხოვს თვითმასპინძელ გარემოს და იმ სერთიფიკატს (credential), რომლითაც Tuist იწყებს სესიებს:

1. **შექმენით გარემო.** Claude Console-ში, [Environments](https://platform.claude.com/environments) გვერდზე შექმენით თვითმასპინძელი გარემო, გახსენით ის და დააჭირეთ **Generate environment key**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ სერთიფიკატი** ფორმის ზედა ნაწილში მდებარე სელექტორის მეშვეობით (იხილეთ ქვემოთ).
3. **ჩასვით გარემოს ID და გასაღები** და აირჩიეთ გარემოს sandbox-ების პლატფორმა და კონფიგურაცია (shape).

Tuist ინახავს მონაცემების შენახვამდე იღებს გარემოს სერთიფიკატის გამოყენებით, ამიტომ არასწორი სერთიფიკატი, ID ან workspace ფორმაში შეცდომას გამოიწვევს. გასაღებები ინახება დაშიფრული და მათი ჩვენება აღარ ხდება. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების (shapes) სანახავად იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ეს არის ნაგულისხმები და sandbox-ების საცდელად ყველაზე სწრაფი გზა. ჩასვით API გასაღები, რომელსაც აქვს დეველოპერის როლი გარემოს workspace-ში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც იყენებენ API გასაღებს; სანამ მას დაეყრდნობოდეთ, დააკავშირეთ ის ფედერირებული იდენტობით, რათა Tuist-მა არ შეინახოს ხანგრძლივი ვადის გასაღები.

#### ფედერირებული იდენტობით {#managed-agents-connect-federated}

Tuist ავტორიზაციას გადის Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ის მეშვეობით, ამიტომ თქვენ არასდროს აწვდით მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ ადმინისტრატორის როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის გამომცემლის URL-ს და subject-ის პრეფიქსს. Claude Console-ში გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` სკოპით. დაამატეთ ოსტატის მიერ შექმნილი სერვისის ანგარიში გარემოს workspace-ში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **Settings → Organization** განყოფილებაში, ხოლო workspace-ის ID — **Settings → Workspaces** განყოფილებაში. Connect workload დასრულებისას აჩვენებს სერვისის ანგარიშისა და ფედერაციის წესის ID-ებს, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის ტოკენს, Console-ის [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ს მეშვეობით {#managed-agents-connect-api}

ავტომატიზაციიდან დასაკავშირებლად, შექმენით თვითმასპინძელი გარემო [Claude Console-ში](https://platform.claude.com/environments), შექმენით მისი გასაღები და გაგზავნეთ ორივე Tuist-ში:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ს მეშვეობით სესიების დასაწყებად, ასევე გაგზავნეთ ან ოთხი ფედერაციის ID (იხილეთ [დაკავშირება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო ეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`-ს; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი sandbox-ების კონფიგურაციას (shape).

### სესიის დაწყება {#managed-agents-sessions}

თითოეული სესია ეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ ითხოვს.

**Claude API-ს მეშვეობით**, შექმენით სესია ჩვეულებრივად გარემოს ID-ით და დააყენეთ `tuist_platform` სესიის მეტამონაცემებში მნიშვნელობად `macos` ან `linux`:

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

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, აგენტის პირველ ბრუნვამდე საჯარო რეპოზიტორი clone-ით ჩამოტვირთოს sandbox-ში.

**Tuist-ის agent-sessions API-ს მეშვეობით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და clone-ით ჩამოტვირთავს პირად GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

როდესაც ანგარიშს აქვს ერთზე მეტი გარემო, გადაეცით `agent_environment_id`. სესიას შეგიძლიათ მიადევნოთ თვალი `GET /agent-sessions/{id}/events`-ით, უპასუხოთ `POST /agent-sessions/{id}/messages`-ით და დაასრულოთ `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორი იშლება (checkout) `/workspace`-ში Linux-ზე და `/Users/runner/work`-ში macOS-ზე. სესიის sandbox ჩერდება (pauses) აგენტის ბრუნვის დასრულების შემდეგ და განახლდება (resumes) შემდეგი შეტყობინებისას.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია შექმნას სესიები Claude workspace-ში, რომელიც ფლობს გარემოს, შეუძლია გაუშვას სესიები თქვენს Tuist ანგარიშზე და მოითხოვოს macOS სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა ამ workspace-ზე.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფა (dashboard) ამას თქვენთვის აწყობს. API-ს მეშვეობით, Tuist იგივენაირად მუშაობს: ყოველ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და ხელს აწერს ხანმოკლე ტოკენს Anthropic-ის ყოველი გამოძახებისთვის, რომელსაც ის ცვლის Anthropic-ის წვდომის ტოკენზე, რომელიც რამდენიმე წუთს ძლებს. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აწერს.

- ყველი აგენტის გარემოს პასუხი შეიცავს `federation_issuer_url`-ს და `federation_subject`-ს (`account:123:agent-environment:456`). Console-ის Custom OIDC ოსტატში გამოიყენეთ გამომცემლის URL და ან ეს ზუსტი subject, რათა მხოლოდ ეს გარემო დაუშვათ, ან `account:123:*` ანგარიშის ყველა გარემოს დასაშვებად. დაფის (dashboard) დაყენების შემოწმებები იყენებენ subject-ს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოპი `workspace:developer`.
- გაგზავნეთ ორგანიზაციის, workspace-ის, სერვისის ანგარიშისა და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ის მეშვეობით. როდესაც გარემოს აქვს როგორც ID-ები, ისე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით, პორტ 443-ზე, საჯარო ჰოსტნეიმიდან. თუ თქვენი self-hosted Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო Console-ში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი აწვდის მისამართზე `<issuer>/jwks.json`. გაიმეორეთ ეს ყოველ ჯერზე, როდესაც Tuist-ის ხელმოწერის გასაღები იცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, თუ ის დაყენებული არ არის, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ის, რასაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის desktop და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია მისი გარემოს მიხედვით, ამიტომ დააკავშირეთ ერთი გარემო თითოეული პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude-ის ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავე გვერდზე შექმენით self-hosted გარემო თითოეული პლატფორმისთვის, ისეთი სახელით, რასაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. დააკავშირეთ თითოეული გარემო თქვენს Tuist ანგარიშთან, სადაც `kind` დაყენებულია `claude_code`-ზე და მითითებულია მისი პლატფორმა:

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

   გაიმეორეთ `"platform": "linux"`-ით და მეორე გარემოს ID-ითა და გასაღებით.

ერთი წუთის განმავლობაში გარემოები მზად იქნება სესიების მისაღებად. უმოქმედო სესია თავის sandbox-ს 30 წუთის განმავლობაში გაშვებულს ტოვებს, შემდეგ კი აჩერებს; სესიის შემდეგი შეტყობინება იმავე sandbox-ს განაახლებს. შეცვალეთ მოლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### აირჩიეთ Linux ან macOS {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც ღრუბლოვან სესიას იწყებენ:

- **claude.ai, desktop და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ მასზე გაეშვება. ერთი სესიისთვის არჩევისას გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად, რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას ჩვეულებრივად, ხოლო მათი sandboxes ითვლება თქვენს Tuist ანგარიშში.

### სესიებისა და ბილდების უფრო სწრაფი გაშვება {#claude-code-caching}

- **Tuist cache:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს cache იმავე rack-ში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და სესიაში არსებული `tuist_ex` Mix task-ები თავისთავად ავტორიზდებიან სესიის identity token-ით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავტორიზაციის სახელმძღვანელოში.
- **Cached checkouts:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია სესიის რეპოზიტორიის წაკითხვა, ახალი სესია იწყება იმავე cached checkout-დან, რომელსაც თქვენი Tuist runner-ები იყენებენ, ამიტომ ის მხოლოდ იმ კომიტებს იწერს, რომლებიც აკლია, ნაცვლად სრული კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმევი შტოს უახლესი კომიტის ობიექტებს, რაც cached checkout-ს აქტუალურს ტოვებს მაშინაც კი, როდესაც რეპოზიტორიები Tuist-ზე CI-ს არ ატარებენ. მას მხოლოდ GitHub-ის მიერ ნაგულისხმევი შტოსთვის მოხსენებული კომიტი ანახლებს; სესიის საკუთარი შტოები ამას არასდროს აკეთებენ. გამორთეთ sandboxes ან წაშალეთ აპლიკაცია ამის შესაჩერებლად.
- **macOS:** Mac-ი იზიარებს Claude Code-ის ბილდის სესიებს, რომლებიც თითოეულ VM-ზე გაეშვება, ამიტომ ახალი სესია მას არ ჩამოტვირთავს.

## Mac-ის გამოყენება ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code-ის სესიები, რომლებიც Linux-ზე გაეშვებიან, მაგალითად, ღრუბლოვანი სესიები Anthropic-ის მიერ hosted გარემოში, მაინც შეუძლიათ Apple-პლატფორმის კოდის აწყობა და ტესტირება Tuist macOS sandbox-ზე, როგორც აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. **Tuist macOS** გარემოსგან განსხვავებით, სესია ინარჩუნებს საკუთარ გარემოს.

**Tuist Linux** გარემოში არაფრის დაყენებაა საჭირო: Tuist CLI და Tuist MCP სერვერი უკვე დაყენებულია და ავტორიზდება სესიის identity-ით.

ღრუბლოვანი სესიებისთვის Anthropic-ის მიერ hosted გარემოში:

1. გახადეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> ხელმისაწვდომი სესიებისთვის: დაამატეთ `https://tuist.dev/mcp` როგორც connector claude.ai-ში და ჩართეთ ის სესიისთვის, ან განაცხადეთ ის რეპოზიტორიის commited `.mcp.json`-ში.
2. დააყენეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად, `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში, როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს გარემოს, შეუძლია მისი წაკითხვა, ამიტომ არ მისცეთ მას სხვა სკოპი, თუ მათ ასევე არ შეუძლიათ თქვენი cache-ის გამოყენება: Mac-ის ბრძანებები იღებენ <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>-ს მხოლოდ იმ ფარგლებში, რაც ტოკენს აქვს, ამიტომ დაამატეთ `ci` Mac-ზე ბილდებისთვის, რათა მათ შეძლონ თქვენი cache-ის წაკითხვა და ჩაწერა.
4. მიეცით გარემოს Tuist-თან მიღწევის საშუალება. Anthropic-ის ნაგულისხმევი **Trusted** ქსელური წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, შეინარჩუნეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI ტვირთავს სესიის ფაილებს Mac-ზე `tuist.dev`-ის მეშვეობით, ამიტომ სხვა დომენი არ სჭირდება.

პირველი სინქრონიზაციის შემდეგ, Claude ასრულებს `mise install`-ს Mac-ზე რეპოზიტორიის root-ში, რათა დააყენოს პროექტის pinned Tuist; Tuist 4.218.0 და მოგვიანებითი ვერსიები შემდეგ თავისთავად ავტორიზდებიან თქვენი ანგარიშის cache-ში ყოველ ბრძანებაში.

Claude შლის Mac-ს, როდესაც დავალება დასრულდება. დარჩენილი Mac იჩერებს მუშაობას უმოქმედობისას და იშლება 14 დღის შეჩერების შემდეგ. ამ გზით შექმნილი Mac-ები ითვლება თქვენს Tuist ანგარიშში, როგორც ნებისმიერი სხვა sandbox.
