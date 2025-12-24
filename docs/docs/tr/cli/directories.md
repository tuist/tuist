---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Dizinler {#directories}

Tuist, [XDG Temel Dizin
Spesifikasyonu](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)'nu
izleyerek dosyalarını sisteminizdeki çeşitli dizinler arasında düzenler. Bu,
yapılandırma, önbellek ve durum dosyalarını yönetmek için temiz ve standart bir
yol sağlar.

## Desteklenen ortam değişkenleri {#supported-environment-variables}

Tuist hem standart XDG değişkenlerini hem de Tuist'e özgü ön ekli değişkenleri
destekler. Tuist'e özgü değişkenler ( `TUIST_` ile ön eklenmiş) önceliklidir ve
Tuist'i diğer uygulamalardan ayrı olarak yapılandırmanıza olanak tanır.

### Yapılandırma dizini {#configuration-directory}

**Ortam değişkenleri:**
- `TUIST_XDG_CONFIG_HOME` (önceliklidir)
- `XDG_CONFIG_HOME`

**Varsayılan:** `~/.config/tuist`

**Şunun için kullanılır:**
- Sunucu kimlik bilgileri (`credentials/{host}.json`)

**Örnek:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Önbellek dizini {#cache-directory}

**Ortam değişkenleri:**
- `TUIST_XDG_CACHE_HOME` (önceliklidir)
- `XDG_CACHE_HOME`

**Varsayılan:** `~/.cache/tuist`

**Şunun için kullanılır:**
- **Eklentiler**: İndirilen ve derlenen eklenti önbelleği
- **ProjectDescriptionHelpers**: Derlenmiş proje açıklama yardımcıları
- **Manifestolar**: Önbelleğe alınmış manifesto dosyaları
- **Projeler**: Oluşturulan otomasyon proje önbelleği
- **EditProjects**: Düzenleme komutu için önbellek
- **Runs**: Run analitik verilerini test edin ve oluşturun
- **İkililer**: Yapı ikili dosyaları (ortamlar arasında paylaşılamaz)
- **SelectiveTests**: Seçmeli test önbelleği

**Örnek:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Eyalet rehberi {#state-directory}

**Ortam değişkenleri:**
- `TUIST_XDG_STATE_HOME` (önceliklidir)
- `XDG_STATE_HOME`

**Varsayılan:** `~/.local/state/tuist`

**Şunun için kullanılır:**
- **Günlükler**: Günlük dosyaları (`logs/{uuid}.log`)
- **Kilitler**: Kimlik doğrulama kilit dosyaları (`{handle}.sock`)

**Örnek:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Öncelik sırası {#precedence-order}

Hangi dizinin kullanılacağını belirlerken, Tuist aşağıdaki sırayla ortam
değişkenlerini kontrol eder:

1. **Tuist'e özgü değişken** (örneğin, `TUIST_XDG_CONFIG_HOME`)
2. **Standart XDG değişkeni** (örneğin, `XDG_CONFIG_HOME`)
3. **Varsayılan konum** (örneğin, `~/.config/tuist`)

Bu size şunları sağlar:
- Tüm uygulamalarınızı tutarlı bir şekilde düzenlemek için standart XDG
  değişkenlerini kullanın
- Tuist için farklı konumlara ihtiyacınız olduğunda Tuist'e özgü değişkenlerle
  geçersiz kılın
- Herhangi bir yapılandırma olmadan mantıklı varsayılanlara güvenin

## Yaygın kullanım durumları {#common-use-cases}

### Tuist'in proje başına izole edilmesi {#isolating-tuist-per-project}

Tuist'in önbelleğini ve durumunu proje başına izole etmek isteyebilirsiniz:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### CI/CD ortamları {#ci-cd-environments}

CI ortamlarında geçici dizinler kullanmak isteyebilirsiniz:

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

### Yalıtılmış dizinlerle hata ayıklama {#debugging-with-isolated-directories}

Hata ayıklarken temiz bir sayfa açmak isteyebilirsiniz:

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
