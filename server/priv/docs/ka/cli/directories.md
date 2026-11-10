---
{
  "title": "დირექტორიები",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "გაიგეთ, როგორ აწყობს Tuist კონფიგურაციის, ქეშის და მდგომარეობის დირექტორიებს."
}
---
# დირექტორიები {#directories}

Tuist სისტემაში ფაილებს რამდენიმე დირექტორიაში ანაწილებს, [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)-ის მიხედვით. ეს უზრუნველყოფს კონფიგურაციის, ქეშის და მდგომარეობის ფაილების მართვის სუფთა, სტანდარტულ გზას.

## მხარდაჭერილი გარემოს ცვლადები {#supported-environment-variables}

Tuist მხარს უჭერს როგორც სტანდარტულ XDG ცვლადებს, ისე Tuist-ისთვის სპეციფიკურ პრეფიქსიან ვარიანტებს. Tuist-ისთვის სპეციფიკური ვარიანტები (პრეფიქსით `TUIST_`) აქვთ უპირატესობა, რაც საშუალებას გაძლევთ Tuist სხვა აპლიკაციებისგან ცალკე დააკონფიგურიროთ.

### კონფიგურაციის დირექტორია {#configuration-directory}

**გარემოს ცვლადები:**
- `TUIST_XDG_CONFIG_HOME` (აქვს უპირატესობა)
- `XDG_CONFIG_HOME`

**ნაგულისხმები:** `~/.config/tuist`

**გამოიყენება:**
- სერვერის ავტორიზაციის მონაცემები (`credentials/{host}.json`)

**მაგალითი:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### ქეშის დირექტორია {#cache-directory}

**გარემოს ცვლადები:**
- `TUIST_XDG_CACHE_HOME` (აქვს უპირატესობა)
- `XDG_CACHE_HOME`

**ნაგულისხმები:** `~/.cache/tuist`

**გამოიყენება:**
- **Plugins**: ჩამოტვირთული და კომპილირებული პლაგინების ქეში
- **ProjectDescriptionHelpers**: კომპილირებული პროექტის აღწერის დამხმარეები
- **Manifests**: ქეშირებული მანიფესტის ფაილები
- **Projects**: გენერირებული ავტომატიზაციის პროექტის ქეში
- **EditProjects**: edit ბრძანების ქეში
- **Runs**: ტესტების და ბილდების გაშვების ანალიტიკური მონაცემები
- **Binaries**: ბილდის არტეფაქტების ბინარები (არ არის გაზიარებადი გარემოებს შორის)
- **SelectiveTests**: შერჩევითი ტესტირების ქეში

**მაგალითი:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### მდგომარეობის დირექტორია {#state-directory}

**გარემოს ცვლადები:**
- `TUIST_XDG_STATE_HOME` (აქვს უპირატესობა)
- `XDG_STATE_HOME`

**ნაგულისხმები:** `~/.local/state/tuist`

**გამოიყენება:**
- **Sessions**: სესიის ლოგები და ქსელური ჩანაწერები (`sessions/{uuid}/`)
- **Locks**: ავტორიზაციის ბლოკირების ფაილები (`{handle}.sock`)

**მაგალითი:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## უპირატესობის თანმიმდევრობა {#precedence-order}

როდესაც განისაზღვრება, რომელი დირექტორია გამოიყენოს, Tuist ამოწმებს გარემოს ცვლადებს შემდეგი თანმიმდევრობით:

1. **Tuist-ისთვის სპეციფიკური ცვლადი** (მაგ., `TUIST_XDG_CONFIG_HOME`)
2. **სტანდარტული XDG ცვლადი** (მაგ., `XDG_CONFIG_HOME`)
3. **ნაგულისხმები მდებარეობა** (მაგ., `~/.config/tuist`)

ეს საშუალებას გაძლევთ:
- გამოიყენოთ სტანდარტული XDG ცვლადები ყველა თქვენი აპლიკაციის თანმიმდევრულად ორგანიზებისთვის
- გადაფაროთ Tuist-ისთვის სპეციფიკური ცვლადებით, როდესაც Tuist-ისთვის სხვა მდებარეობები გჭირდებათ
- ენდოთ გონივრულ ნაგულისხმევებს კონფიგურაციის გარეშე

## ტიპური გამოყენების შემთხვევები {#common-use-cases}

### Tuist-ის იზოლირება პროექტის მიხედვით {#isolating-tuist-per-project}

შეგიძლიათ Tuist-ის ქეში და მდგომარეობა თითოეული პროექტისთვის იზოლიროთ:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD გარემოები {#ci-cd-environments}

CI გარემოებში შეიძლება დროებითი დირექტორიების გამოყენება მოგინდეთ:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### დებაგინგი იზოლირებული დირექტორიებით {#debugging-with-isolated-directories}

პრობлемების დებაგინგისას შეიძლება სუფთა საწყისი წერტილი დაგჭირდეთ:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
