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
> Tuist Sandboxes, როგორც Linux-ზე, ისე macOS-ზე, ამჟამად მხოლოდ მოწვევითაა ხელმისაწვდომი. [დაგვიკავშირდით](mailto:contact@tuist.dev) ან მოგვწერეთ [საზოგადოების Slack-ში](https://slack.tuist.dev), რათა თქვენი ანგარიშისთვის წვდომა მოითხოვოთ.

Anthropic მართავს Claude-ის აგენტის ციკლს, ხოლო *თვითმასპინძელი გარემო* განსაზღვრავს, სად გაეშვება Claude-ის ინსტრუმენტები. დააკავშირეთ ერთ-ერთი Tuist-თან და მასში ყოველი სესია მიიღებს საკუთარ Tuist <.localized_link href="/guides/features/sandboxes">სენდბოქსს</.localized_link>, Linux-ზე ან macOS-ზე. Tuist აწარმოებს იმ სამუშაო პროცესებსა და გამშვებებს, რაც ამ გარემოებს სჭირდებათ, ასე რომ, არაფრის ჰოსტინგი არ გჭირდებათ.

არსებობს გარემოების ორი ტიპი, თითო Claude-ის თითოეული პროდუქტისთვის:

- **[Claude Managed Agents](#managed-agents)**: სესიები, რომლებსაც იწყებთ Claude API-ით ან Tuist-ის agent-sessions API-ით. გარემოს (`env_…`) ქმნით [Claude Console-ში](https://platform.claude.com/environments) და თითოეულ სესიას შეუძლია აირჩიოს Linux ან macOS.
- **[Claude Code](#claude-code)**: ღრუბლოვანი სესიები, რომლებსაც დეველოპერები იწყებენ claude.ai-დან, Claude-ის დესკტოპისა და მობილური აპლიკაციებიდან და `claude --cloud`-დან. Claude Team-ის ან Enterprise-ის მფლობელი ქმნის გარემოებს (`ccpool_…`) claude.ai-ის ადმინისტრატორის პარამეტრებში, თითო თითოეული პლატფორმისთვის, ხოლო დეველოპერები ირჩევენ Linux-ს ან macOS-ს გარემოს არჩევით.

ორივე მათგანი Tuist API-ს მეშვეობით ანგარიშის ადმინისტრატორის მიერ არის დაკავშირებული. გაიარეთ ავტორიზაცია `tuist auth login`-ით, შემდეგ:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### გარემოს დაკავშირება {#managed-agents-connect}

1. [Claude Console-ში](https://platform.claude.com/environments) დააჭირეთ **Create environment** და **Hosting**-ის ქვეშ აირჩიეთ **Self-hosted**. გახსენით გარემო, დააჭირეთ **Generate environment key** და დააკოპირეთ გარემოს `env_…` ID და გასაღები. დეტალებისთვის იხილეთ Anthropic-ის [თვითმასპინძელი სენდბოქსების](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes) სახელმძღვანელო.
2. დააკავშირეთ ის თქვენს Tuist ანგარიშთან:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key` არის არასავალდებულო. ის გაძლევთ საშუალებას, დაიწყოთ სესიები Tuist-ის API-ს მეშვეობით, როგორც ქვემოთაა აღწერილი. Tuist ინახავს ორივე გასაღებს დაშიფრულად და არასდროს აბრუნებს მათ.

წუთის განმავლობაში Tuist იწყებს გარემოს სესიების მომსახურებას. გარემო მუშაობს Linux-ზე, თუ არ გადასცემთ `"platform": "darwin"`. ასევე შეგიძლიათ გადასცეთ `vcpus`, `memory_mb` და `workspace_gb`, რათა შეცვალოთ მისი სენდბოქსების კონფიგურაცია; იხილეთ <.localized_link href="/guides/features/sandboxes#platforms">Linux და macOS</.localized_link>.

### სესიის დაწყება {#managed-agents-sessions}

თითოეული სესია მუშაობს გარემოს პლატფორმაზე, თუ სესია სხვას არ მოითხოვს.

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

`repository_url` და, სურვილისამებრ, `repository_ref` (ბრენჩი ან კომიტი) აიძულებს Tuist-ს, დააკლონოს საჯარო რეპოზიტორია სენდბოქსში აგენტის პირველ სვლამდე.

**Tuist-ის agent-sessions API-ს გამოყენებით**, Tuist ქმნის აგენტსა და სესიას თქვენთვის და აკლონებს პირად GitHub რეპოზიტორიებს, რომლებიც დაკავშირებულია თქვენს Tuist ანგარიშთან:

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

როდესაც ანგარიშს ერთზე მეტი გარემო აქვს, გადასცეთ `agent_environment_id`. სესიას შეგიძლიათ მიჰყვეთ `GET /agent-sessions/{id}/events`-ით, უპასუხოთ `POST /agent-sessions/{id}/messages`-ით და დაასრულოთ `POST /agent-sessions/{id}/archive`-ით.

რეპოზიტორია გამოიწერება `/workspace`-ში Linux-ზე და `/Users/runner/work`-ში macOS-ზე. სესიის სენდბოქსი ჩერდება აგენტის სვლის დასრულების შემდეგ და განახლდება შემდეგ შეტყობინებაზე.

> [!WARNING]
> ნებისმიერს, ვისაც შეუძლია შექმნას სესიები Claude workspace-ში, რომელიც ფლობს გარემოს, შეუძლია გაუშვას სესიები თქვენს Tuist ანგარიშზე და მოითხოვოს macOS სესიის მეტამონაცემებით. შესაბამისად, შეზღუდეთ წვდომა იმ workspace-ზე.

## Claude Code {#claude-code}

Claude Code-ის ღრუბლოვანი სესიები არის ისინი, რომლებსაც დეველოპერები იწყებენ [claude.ai/code](https://claude.ai/code)-დან, Claude-ის დესკტოპისა და მობილური აპლიკაციებიდან და `claude --cloud`-დან. ისინი ირჩევენ, სად გაეშვება სესია, მისი გარემოს მიხედვით, ამიტომ დააკავშირეთ ერთი გარემო თითოეული იმ პლატფორმისთვის, რომლის შეთავაზებაც გსურთ.

### გარემოების დაკავშირება {#claude-code-connect}

1. Claude ორგანიზაციის მფლობელი რთავს **Allow self-hosted environments**-ს [Cloud environments](https://claude.ai/admin-settings/cloud-environments) ადმინისტრატორის გვერდზე. ამისთვის საჭიროა Team ან Enterprise გეგმა; იხილეთ Anthropic-ის [თვითმასპინძელი გარემოების](https://code.claude.com/docs/en/self-hosted-environments) სახელმძღვანელო.
2. იმავ გვერდზე შექმენით თვითმასპინძელი გარემო თითოეული პლატფორმისთვის, იმ სახელით, რომელსაც დეველოპერები ნახავენ, მაგალითად **Tuist Linux** და **Tuist macOS**. დააკოპირეთ თითოეული გარემოს `ccpool_…` ID და მისი გარემოს გასაღები, რომელიც მხოლოდ ერთხელ ჩანს.
3. დააკავშირეთ თითოეული გარემო თქვენს Tuist ანგარიშთან `kind`-ის მნიშვნელობად `claude_code` და მისი პლატფორმის მითითებით:

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

წუთის განმავლობაში გარემოები მზად იქნება სესიების მიღებისთვის. უმოქმედო სესია ინარჩუნებს თავის სენდბოქსს გაშვებულს 30 წუთის განმავლობაში, შემდეგ აჩერებს მას; სესიის შემდეგი შეტყობინება განაახლებს იმავე სენდბოქსს. შეცვალეთ ლოდინის დრო `max_idle_seconds`-ით (3600-მდე).

### Linux-ის ან macOS-ის არჩევა {#claude-code-choose}

დეველოპერები ირჩევენ გარემოს და, შესაბამისად, პლატფორმას, როდესაც იწყებენ ღრუბლოვან სესიას:

- **claude.ai, დესკტოპისა და მობილური აპლიკაციები:** აირჩიეთ **Tuist Linux** ან **Tuist macOS** ახალი სესიის გარემოს ამრჩევში.
- **Claude Code CLI:** გაუშვით `/remote-env` `claude`-ში და აირჩიეთ გარემო სახელით. `claude --cloud "<task>"` შემდეგ მასზე გაეშვება. ერთი სესიისთვის არჩევისას გადასცეთ მისი ID: `claude --cloud "<task>" --environment ccpool_...`.
- **მთელი გუნდი ან რეპოზიტორია:** დააყენეთ ნაგულისხმევი გარემოს ID Claude Code-ის [პარამეტრებში](https://code.claude.com/docs/en/settings), მაგალითად, რეპოზიტორიის `.claude/settings.json`-ში:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

ამ გარემოებში სესიები იყენებენ თქვენი ორგანიზაციის Claude Code-ის გამოყენებას ჩვეულებრივად და მათი სენდბოქსები ითვლება თქვენი Tuist ანგარიშის ლიმიტში.
