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
> Tuist Sandboxes, როგორც Linux-ზე, ისე macOS-ზე, ამჟამად მხოლოდ მიწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენი ანგარიშისთვის წვდომა მოითხოვოთ.

Anthropic მართავს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ერთ-ერთი Tuist-თან და მასში არსებული ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">სენდბოქსს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist აწარმოებს იმ სამუშაო პროცესებსა და გამშვებებს, რომლებიც ამ გარემოებს სჭირდებათ, ასე რომ, თქვენ არაფრის ჰოსტინგი არ გჭირდებათ.

არსებობს გარემოების ორი ტიპი, თითოეული Claude-ის პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც თქვენ იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. თქვენ ქმნით გარემოს (`env_…`) [Claude Console](https://platform.claude.com/environments)-ში და ყოველ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team ან Enterprise მფლობელი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორულ პარამეტრებში, თითოეული პლატფორმისთვის ერთს, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს გარემოს არჩევით.

ორივე მათგანი Tuist API-ს მეშვეობით აკავშირებს ანგარიშის ადმინისტრატორი. გაიარეთ ავთენტიკაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

დაუკავშირდით თქვენი ანგარიშის **Settings → Integrations → Claude** განყოფილებიდან. ფორმა ითხოვს თვითმასპინძელ გარემოს და კრედენციალს, რომლითაც Tuist იწყებს სესიებს:

1. **შექმენით გარემო.** Claude Console-ში, [Environments](https://platform.claude.com/environments) გვერდზე შექმენით თვითმასპინძელი გარემო, გახსენით ის და დააჭირეთ **Generate environment key**. Anthropic გარემოს გასაღებებს მხოლოდ Console-ში ქმნის.
2. **აირჩიეთ კრედენციალი** ფორმის ზედა ნაწილში არსებული სელექტორით (იხილეთ ქვემოთ).
3. **ჩასვით გარემოს ID და გასაღები** და აირჩიეთ გარემოს სენდბოქსების პლატფორმა და კონფიგურაცია.

Tuist იღებს გარემოს კრედენციალით, სანამ რაიმეს შეინახავს, ამიტომ არასწორი კრედენციალი, ID ან სამუშაო სივრცე ფორმაში შეცდომას გამოიწვევს. ის გასაღებებს დაშიფრულად ინახავს და აღარასდროს აჩვენებს. ერთი წუთის განმავლობაში, Tuist იწყებს გარემოს სესიების მომსახურებას. კონფიგურაციების შესახებ იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

#### API გასაღებით {#managed-agents-connect-api-key}

ეს არის ნაგულისხმები და სენდბოქსების სწრაფად გამოსაცდელი გზა. ჩასვით API გასაღები დეველოპერის როლით გარემოს სამუშაო სივრცეში. ინტეგრაცია აღნიშნავს გარემოებს, რომლებიც API გასაღებს იყენებენ; სანამ ერთ-ერთს დაეყრდნობოდეთ, უმჯობესია დააკავშიროთ ის ფედერირებული იდენტობით, რათა Tuist-მა არ შეინახოს ხანგრძლივი ვადის გასაღები.

#### ფედერირებული იდენტობით {#managed-agents-connect-federated}

Tuist ავთენტიკაციას გადის Anthropic-ის [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)-ით, ამიტომ თქვენ არასდროს აწვდით მას Anthropic-ის API გასაღებს. თქვენ გჭირდებათ ადმინისტრატორის როლი თქვენს Anthropic ორგანიზაციაში.

1. **ენდეთ Tuist-ს.** ფორმა აჩვენებს თქვენი ანგარიშის გამომცემლის URL-ს და სუბიექტის პრეფიქსს. Claude Console-ში გახსენით [Workload identity](https://platform.claude.com/settings/workload-identity-federation), დააჭირეთ **Connect workload**, აირჩიეთ **Custom OIDC** და შეიყვანეთ ისინი `workspace:developer` სკოპით. დაამატეთ ვიზარდის მიერ შექმნილი სერვისის ანგარიში გარემოს სამუშაო სივრცეში.
2. **შეიყვანეთ ID-ები.** ორგანიზაციის ID მდებარეობს **Settings → Organization** ქვეშ, ხოლო სამუშაო სივრცის ID — **Settings → Workspaces** ქვეშ. Connect workload აჩვენებს სერვისის ანგარიშისა და ფედერაციის წესის ID-ებს დასრულებისას, ხოლო Workload identity-ში წესის გვერდი მათ კიდევ ერთხელ აჩვენებს. არცერთი მათგანი არ არის საიდუმლო. თუ Anthropic უარყოფს Tuist-ის ტოკენს, Console-ის [ავთენტიკაციის ისტორია](https://platform.claude.com/settings/workload-identity-federation?tab=history) აჩვენებს მიზეზს.

#### API-ით {#managed-agents-connect-api}

ავტომატიზაციიდან დასაკავშირებლად, შექმენით თვითმასპინძელი გარემო [Claude Console](https://platform.claude.com/environments)-ში, შექმენით მისი გასაღები და გაუგზავნეთ ორივე Tuist-ს:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Tuist-ის API-ს მეშვეობით სესიების დასაწყებად, ასევე გაუგზავნეთ ან ოთხი ფედერაციის ID (იხილეთ [დაკავშირება API გასაღების გარეშე](#managed-agents-federation)) ან `anthropic_api_key`. გარემო ეშვება Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`; `vcpus`, `memory_mb` და `workspace_gb` ცვლიან მისი სენდბოქსების კონფიგურაციას.

### სესიის დაწყება {#managed-agents-sessions}

ყოველი სესია ეშვება გარემოს პლატფორმაზე, თუ სესია სხვას არ მოითხოვს.

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

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, დააკლონოს საჯარო რეპოზიტორია სენდბოქსში, სანამ აგენტი პირველ ბრუნვას შეასრულებს.

**Tuist-ის agent-sessions API-ით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და აკლონებს კერძო GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

რეპოზიტორია იღება `/workspace`-ში Linux-ზე და `/Users/runner/work`-ში macOS-ზე. სესიის სენდბოქსი ჩერდება აგენტის ბრუნვის დასრულების შემდეგ და განახლდება შემდეგი შეტყობინებისას.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია შექმნას სესიები Claude-ის სამუშაო სივრცეში, რომელიც ფლობს გარემოს, შეუძლია გაუშვას სესიები თქვენს Tuist ანგარიშზე და მოითხოვოს macOS სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა იმ სამუშაო სივრცეზე.

### დაკავშირება API გასაღების გარეშე {#managed-agents-federation}

დაფა ამას თქვენთვის აკეთებს. API-ს მეშვეობით, Tuist იგივენაირად მუშაობს: ყოველ ანგარიშს აქვს საკუთარი OpenID Connect გამომცემელი Tuist-ზე, `https://tuist.dev/oidc/accounts/<account id>`, და აფორმებს ხანმოკლე ტოკენს Anthropic-ის ყოველი გამოძახებისთვის, რომელსაც ის ცვლის Anthropic-ის წვდომის ტოკენზე, რომელიც რამდენიმე წუთი ძლებს. ფედერაციის წესი, რომელიც ენდობა თქვენს გამომცემელს, არასდროს იღებს ტოკენებს, რომლებსაც Tuist სხვა ანგარიშებისთვის აფორმებს.

- ყოველი აგენტის გარემოს პასუხი შეიცავს `federation_issuer_url`-ს და `federation_subject`-ს (`account:123:agent-environment:456`). Console-ის Custom OIDC ვიზარდში, გამოიყენეთ გამომცემლის URL და ან ზუსტად ეს სუბიექტი, რათა მხოლოდ ეს გარემო დაუშვათ, ან `account:123:*` ანგარიშის ყოველი გარემოს დასაშვებად. დაფის პარამეტრების შემოწმებები იყენებენ სუბიექტს `account:123:setup`, რომელსაც მხოლოდ პრეფიქსი უშვებს. გამოიყენეთ სკოპი `workspace:developer`.
- გაუგზავნეთ ორგანიზაციის, სამუშაო სივრცის, სერვისის ანგარიშისა და წესის ID-ები, როგორც `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` და `anthropic_federation_rule_id`, შექმნისას ან `PATCH /agent-environments/{id}`-ით. როდესაც გარემოს აქვს როგორც ID-ები, ასევე API გასაღები, Tuist იყენებს ფედერაციას.

> [!NOTE]
> Anthropic იღებს გამომცემლის გასაღებებს HTTPS-ით 443 პორტზე საჯარო ჰოსტნეიმიდან. თუ თქვენი თვითგანთავსებული Tuist სერვერი ინტერნეტიდან მიუწვდომელია, აირჩიეთ **inline** JWKS წყარო Console-ში და ჩასვით გასაღებების ნაკრები, რომელსაც თქვენი სერვერი ემსახურება მისამართზე `<issuer>/jwks.json`. გაიმეორეთ ეს ყოველ ჯერზე, როდესაც Tuist-ის ხელმოწერის გასაღები შეიცვლება, რაც ხდება მაშინ, როდესაც სერვერის `TUIST_SECRET_KEY_TOKENS` (ან, როდესაც ის არ არის დაყენებული, `TUIST_SECRET_KEY_BASE`) იცვლება.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ის, რასაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის დესკტოპ და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია, მისი გარემოს მიხედვით, ამიტომ თქვენ უნდა დააკავშიროთ ერთი გარემო თითოეული პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავე გვერდზე, შექმენით თვითგანთავსებული გარემო თითოეული პლატფორმისთვის, იმ სახელით, რასაც დეველოპერები დაინახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
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

   გაიმეორეთ `"platform": "linux"`-ით და მეორე გარემოს ID-ითა და გასაღებით.

ერთი წუთის განმავლობაში, გარემოები მზად იქნება სესიების მისაღებად. უმოქმედო სესია თავის sandbox-ს 30 წუთის განმავლობაში აქტიურად ტოვებს, შემდეგ კი აჩერებს; სესიის შემდეგი შეტყობინება იმავე sandbox-ს აღადგენს. შეცვალეთ მოლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### აირჩიეთ Linux ან macOS {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც ისინი იწყებენ ღრუბლოვან სესიას:

- **claude.ai, დესკტოპ და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ მასზე გაეშვება. ერთი სესიისთვის რომ აირჩიოთ, გადაეცით მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [settings](https://code.claude.com/docs/en/settings)-ში, მაგალითად, რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას ჩვეულებრივად, და მათი sandboxes ითვლება თქვენს Tuist ანგარიშზე.

### სესიების უფრო სწრაფი გაშვება და ბილდები {#claude-code-caching}

- **Tuist cache:** სესიები იღებენ `TUIST_URL`-ს და, როდესაც თქვენს ანგარიშს აქვს cache იმავე rack-ში, `TUIST_CACHE_ENDPOINT`-ს. Tuist CLI და სესიაში არსებული `tuist_ex` Mix tasks თავისთავად შედიან სესიის იდენტობის ტოკენით. იხილეთ <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link> ავთენტიკაციის სახელმძღვანელოში.
- **Cached checkouts:** როდესაც თქვენი ანგარიშის Tuist GitHub აპლიკაციას შეუძლია სესიის რეპოზიტორიის წაკითხვა, ახალი სესია იწყება იმავე cached checkout-დან, რომელსაც თქვენი Tuist runners იყენებენ, ამიტომ ის მხოლოდ იმ კომიტებს იღებს, რაც აკლია, ნაცვლად კლონირებისა. როდესაც სესია მთავრდება, ის აბრუნებს ნაგულისხმევი შტოს უახლესი კომიტის ობიექტებს, რაც cached checkout-ს აქტუალურს ტოვებს მაშინაც კი, რეპოზიტორიებისთვის, რომლებიც Tuist-ზე CI-ს არ აწარმოებენ. მხოლოდ ის კომიტი, რომელსაც GitHub აცხობს ნაგულისხმევი შტოსთვის, ანახლებს მას; სესიის საკუთარი შტოები არასდროს. გამორთეთ sandboxes ან წაშალეთ აპლიკაცია ამის შესაჩერებლად.
- **macOS:** Mac-ი იზიარებს Claude Code build სესიებს, რომლებიც თითოეულ VM-ზე გაეშვება, ამიტომ ახალი სესია მას არ ჩამოტვირთავს.

## Mac-ის გამოყენება ნებისმიერი Claude Code სესიიდან {#remote-mac}

Claude Code სესიები, რომლებიც Linux-ზე გაეშვება, როგორიცაა ღრუბლოვანი სესიები Anthropic-ის მიერ განთავსებულ გარემოში, მაინც შეუძლიათ Apple-პლატფორმის კოდის აგება და ტესტირება Tuist macOS sandbox-ზე, როგორც აღწერილია <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>-ში. **Tuist macOS** გარემოსგან განსხვავებით, სესია ინარჩუნებს საკუთარ გარემოს.

**Tuist Linux** გარემოში არაფერია დასაყენებელი: Tuist CLI და Tuist MCP server უკვე დაყენებულია და შედიან სესიის იდენტობით.

ღრუბლოვანი სესიებისთვის Anthropic-ის მიერ განთავსებულ გარემოში:

1. გაუწვდომეთ Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> სესიებისთვის: დაამატეთ `https://tuist.dev/mcp` როგორც connector claude.ai-ში და ჩართეთ ის სესიისთვის, ან განაცხადეთ ის რეპოზიტორიის commited `.mcp.json`-ში.
2. დააყენეთ Tuist CLI გარემოს [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)-ში, მაგალითად, `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`-ით.
3. შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `account:sandboxes:write` სკოპით და დაამატეთ ის გარემოს [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)-ში, როგორც `TUIST_TOKEN`. ყველას, ვინც იყენებს გარემოს, შეუძლია მისი წაკითხვა, ამიტომ სხვა სკოპი არ მისცეთ.
4. მიეცით გარემოს Tuist-თან მიღწევის საშუალება. Anthropic-ის ნაგულისხმევი **Trusted** ქსელის წვდომა არ მოიცავს `tuist.dev`-ს, ამიტომ აირჩიეთ **Custom**, დატოვეთ ნაგულისხმევი დომენები და დაამატეთ `tuist.dev` **Allowed domains**-ში. CLI ატვირთავს სესიის ფაილებს Mac-ზე `tuist.dev`-ის მეშვეობით, ამიტომ სხვა დომენი არ სჭირდება.

Claude შლის Mac-ს, როდესაც დავალება დასრულდება. დარჩენილი Mac იჩერებს მუშაობას უმოქმედობისას და იშლება 14 დღიანი შეჩერების შემდეგ. ასე შექმნილი Mac-ები ითვლება თქვენს Tuist ანგარიშზე, როგორც ნებისმიერი სხვა sandbox.
