---
{
  "title": "Claude",
  "titleTemplate": ":title · სენდბოქსები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაუშვით Claude Managed Agents-ის სესიები და Claude Code-ის ღრუბლოვანი სესიები (claude.ai, დესკტოპისა და მობილური აპლიკაციები და claude --cloud) Tuist-ის სენდბოქსებზე, Linux-ზე ან macOS-ზე."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **მხოლოდ მიწვევით**
>
> Tuist Sandboxes, როგორც Linux-ის, ისე macOS-ის ვერსიები, ამჟამად მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენი ანგარიშისთვის წვდომა მოითხოვოთ.

Anthropic უზრუნველყოფს Claude-ის აგენტის ციკლის შესრულებას, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ იგი Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">სენდბოქსს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist აწარმოებს იმ მუშაკებსა და გამშვებებს, რომლებიც ამ გარემოებს სჭირდებათ, ასე რომ, თქვენ არაფერს მასპინძლობთ.

არსებობს გარემოების ორი ტიპი, თითოეული Claude-ის პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც თქვენ იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. გარემოს (`env_…`) ქმნით [Claude Console-ში](https://platform.claude.com/environments) და თითოეულ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის დესკტოპისა და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team-ის ან Enterprise-ის მფლობელი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორის პარამეტრებში, თითოეული პლატფორმისთვის ერთს, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს გარემოს არჩევით.

ორივე მათგანი Tuist API-ს მეშვეობით ანგარიშის ადმინისტრატორის მიერ არის დაკავშირებული. გაიარეთ ავთენტიფიკაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

დაუკავშირდით თქვენი ანგარიშის **პარამეტრები → ინტეგრაციები → Claude** მენიუს. ფორმა ითხოვს თვითმასპინძელ გარემოს და კრედენციალს, რომლითაც Tuist იწყებს სესიებს:

1. **შექმენით გარემო.** Claude Console-ში, [გარემოების](https://platform.claude.com/environments) გვერდზე შექმენით თვითმასპინძელი გარემო, გახსენით იგი და დააჭირეთ **გარემოს გასაღების გენერირება**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ კრედენციალი** ფორმის ზედა ნაწილში მდებარე სელექტორის გამოყენებით (იხილეთ ქვემოთ).
3. **ჩასვით გარემოს ID და გასაღები** და აირჩიეთ გარემოს სენდბოქსების პლატფორმა და კონფიგურაცია.

Tuist ინახავს რაიმეს შენახვამდე იძენს გარემოს კრედენციალის გამოყენებით, ამიტომ არასწორი კრედენციალი, ID ან სამუშაო სივრცე ფორმაში შეცდომას გამოიწვევს. ის გასაღებებს დაშიფრულად ინახავს და აღარასდროს აჩვენებს. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების სანახავად იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ნაგულისხმევი და სენდბოქსების სწრაფად გამოსაცდელი გზა. ჩასვით API გასაღები დეველოპერის როლით გარემოს სამუშაო სივრცეში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც იყენებენ API გასაღებს; სანამ მას დაეყრდნობოდეთ, დააკავშირეთ იგი ფედერირებული იდენტობით, რათა Tuist-მა არ შეინახოს ხანგრძლივი მოქმედების გასაღები.

#### ფედერირებული იდენტობით {#managed-agents-connect-federated}

Tuist ავთენტიფიცირდება Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ით, ასე რომ, თქვენ არასდროს აძლევთ მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ ადმინისტრატორის როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის გამომცემლის URL-ს და სუბიექტის პრეფიქსს. Claude Console-ში გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` სკოპით. დაამატეთ ვიზარდის მიერ შექმნილი სერვისის ანგარიში გარემოს სამუშაო სივრცეში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **პარამეტრები → ორგანიზაცია** ქვეშ, ხოლო სამუშაო სივრცის ID — **პარამეტრები → სამუშაო სივრცეები** ქვეშ. Connect workload დასრულებისას აჩვენებს სერვისის ანგარიშისა და ფედერაციის წესის ID-ებს, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის ტოკენს, Console-ის [ავთენტიფიკაციის ისტორია](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ს გამოყენებით {#managed-agents-connect-api}

ავტომატიზაციიდან დასაკავშირებლად, შექმენით თვითმასპინძელი გარემო [Claude Console-ში](https://platform.claude.com/environments), შექმენით მისი გასაღები და გაგზავნეთ ორივე Tuist-ში:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ს მეშვეობით სესიების დასაწყებად, ასევე გაგზავნეთ ან ოთხი ფედერაციის ID (იხილეთ [დაკავშირება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო გაეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი სენდბოქსების კონფიგურაციას.

### სესიის დაწყება {#managed-agents-sessions}

თითოეული სესია გაეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ ითხოვს.

**Claude API-ს გამოყენებით**, შექმენით სესია ჩვეულებრივად გარემოს ID-ით და დააყენეთ `tuist_platform` სესიის მეტამონაცემებში `macos` ან `linux` მნიშვნელობად:

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

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, დააკლონოს საჯარო რეპოზიტორია სენდბოქსში აგენტის პირველ ბრუნამდე.

**Tuist-ის agent-sessions API-ს გამოყენებით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და აკლონებს კერძო GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

როდესაც ანგარიშს ერთზე მეტი გარემო აქვს, გადასცეთ `agent_environment_id`. სესიის თვალყურის დევნა შეგიძლიათ `GET /agent-sessions/{id}/events`-ით, პასუხის გაგზავნა `POST /agent-sessions/{id}/messages`-ით და მისი დასრულება `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორია იღება `/workspace`-ში Linux-ზე და `/Users/runner/work`-ში macOS-ზე. სესიის სენდბოქსი ჩერდება აგენტის ბრუნის დასრულების შემდეგ და განახლდება შემდეგ შეტყობინებაზე.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია შექმნას სესიები Claude-ის სამუშაო სივრცეში, რომელიც ფლობს გარემოს, შეუძლია გაუშვას სესიები თქვენს Tuist ანგარიშზე და მოითხოვოს macOS სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა ამ სამუშაო სივრცეში.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფისბორდი ამას თქვენთვის აწყობს. API-ს მეშვეობით, Tuist იგივე გზით მუშაობს: თითოეულ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და ხელს აწერს ხანმოკლე ტოკენს Anthropic-თან ყოველი ზარისთვის, რომელსაც ის ცვლის Anthropic-ის წვდომის ტოკენზე, რომელიც რამდენიმე წუთი ძლებს. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აწერს.

- აგენტის გარემოს ყოველი პასუხი შეიცავს `federation_issuer_url` და `federation_subject` (`account:123:agent-environment:456`). Console-ის Custom OIDC ვიზარდში გამოიყენეთ გამომცემლის URL და ან ეს ზუსტი სუბიექტი, რათა დაუშვათ მხოლოდ ეს გარემო, ან `account:123:*` ანგარიშის ყოველი გარემოს დასაშვებად. დაფისბორდის პარამეტრების შემოწმებები იყენებენ სუბიექტს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოპი `workspace:developer`.
- გაგზავნეთ ორგანიზაციის, სამუშაო სივრცის, სერვისის ანგარიშისა და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ით. როდესაც გარემოს აქვს როგორც ID-ები, ისე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით, 443 პორტზე, საჯარო ჰოსტნეიმიდან. თუ თქვენი საკუთარ სერვერზე განთავსებული Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო Console-ში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი ემსახურება მისამართზე `<issuer>/jwks.json`. გაიმეორეთ ეს ყოველთვის, როდესაც Tuist-ის ხელმოწერის გასაღები იცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, თუ ის დაყენებული არ არის, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ის, რასაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია, მისი გარემოს მიხედვით, ამიტომ შეაერთეთ ერთი გარემო თითოეული პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების შეერთება {#claude-code-connect}

1. Claude-ის ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავდროულად, იმავე გვერდზე შექმენით საკუთარ სერვერზე განთავსებული გარემო თითოეული პლატფორმისთვის, იმ სახელით, რომელსაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. შეაერთეთ თითოეული გარემო თქვენს Tuist ანგარიშთან, სადაც `kind` დაყენებულია `claude_code`-ზე და მითითებულია მისი პლატფორმა:

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

   გაიმეორეთ იგივე `"platform": "linux"`-ით და მეორე გარემოს ID-ით და გასაღებით.

ერთი წუთის განმავლობაში გარემოები მზად იქნება სესიების მიღებისთვის. უმოქმედო სესია თავის sandbox-ს 30 წუთის განმავლობაში აქტიურად ტოვებს, შემდეგ კი აჩერებს; სესიის შემდეგი შეტყობინება იმავე sandbox-ს აღადგენს. შეცვალეთ მოლოდინის დრო `max_idle_seconds`-ით (მაქსიმუმ 3600).

### აირჩიეთ Linux ან macOS {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც ღრუბლოვან სესიას იწყებენ:

- **claude.ai, დესკტოპ და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ მასზე გაეშვება. ერთი სესიისთვის არჩევისას, გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად, რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები ჩვეულებრივად იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას და მათი sandbox-ები ითვლება თქვენი Tuist ანგარიშის ლიმიტში.

### სესიების უფრო სწრაფი გაშვება და ბილდები {#claude-code-caching}

- **Tuist cache:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს ქეში იმავე რაკში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და სესიაში არსებული `tuist_ex` Mix ამოცანები თავისთავად ავტორიზდებიან სესიის იდენტობის ტოკენით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავტორიზაციის სახელმძღვანელოში.
- **Cached checkouts:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია სესიის რეპოზიტორიის წაკითხვა, ახალი სესია იწყება იმავე ქეშირებული checkout-დან, რომელსაც თქვენი Tuist რანერები იყენებენ, ამიტომ ის მხოლოდ იმ კომიტებს იწერს, რომლებიც აკლია, ნაცვლად სრული კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმევი შტოს უახლესი კომიტის ობიექტებს, რაც ქეშირებულ checkout-ს აქტუალურს ტოვებს მაშინაც კი, თუ რეპოზიტორიები Tuist-ზე CI-ს არ აწარმოებენ. მას ანახლებს მხოლოდ ის კომიტი, რომელსაც GitHub აცხობს ნაგულისხმევი შტოსთვის; სესიის საკუთარი შტოები ამას არასდროს აკეთებენ. ამის შესაჩერებლად გათიშეთ sandbox-ები ან წაშალეთ აპლიკაცია.
- **macOS:** Mac-ი იზიარებს Claude Code-ის ბილდის სესიებს, რომლებიც თითოეულ VM-ზე გაეშვა, ამიტომ ახალ სესიას მისი ჩამოტვირთვა არ სჭირდება.

## Mac-ის გამოყენება ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code სესიები, რომლებიც Linux-ზე გაეშვება, როგორიცაა ღრუბლოვანი სესიები Anthropic-ის მიერ განთავსებულ გარემოში, მაინც შეუძლიათ Apple-პლატფორმის კოდის აწყობა და ტესტირება Tuist macOS sandbox-ზე, როგორც ეს აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. განსხვავებით **Tuist macOS** გარემოსგან, არაფრის შეერთება არ არის საჭირო და სესია ინარჩუნებს საკუთარ გარემოს. ღრუბლოვანი სესიებისთვის:

1. გაადიდეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> სესიებისთვის ხელმისაწვდომი: დაამატეთ `https://tuist.dev/mcp` როგორც კონექტორი claude.ai-ში და ჩართეთ ის სესიისთვის, ან გამოაცხადეთ ის რეპოზიტორიის კომიტირებულ `.mcp.json`-ში.
2. დააინსტალირეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად, `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში, როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს გარემოს, შეუძლია მისი წაკითხვა, ამიტომ სხვა სკოპი არ მიანიჭოთ.
4. მიეცით გარემოს Tuist-თან მიღწევის საშუალება. Anthropic-ის ნაგულისხმევი **Trusted** ქსელური წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, შეინარჩუნეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI სესიის ფაილებს Mac-ზე `tuist.dev`-ის მეშვეობით ატვირთავს, ამიტომ სხვა დომენი არ სჭირდება.

Claude შლის Mac-ს, როდესაც ამოცანა დასრულებულია. დარჩენილი Mac იჩერებს უმოქმედობისას და იშლება 14 დღიანი შეჩერების შემდეგ. ასე შექმნილი Mac-ები ითვლება თქვენი Tuist ანგარიშის ლიმიტში, როგორც ნებისმიერი სხვა sandbox.
