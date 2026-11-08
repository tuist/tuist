---
{
  "title": "Dizinler",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist'in yapılandırma, önbellek ve durum dizinlerini nasıl organize ettiğini öğrenin."
}
---
# Dizinler {#directories}

Tuist, dosyalarını sisteminizdeki birkaç dizinde [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) standardına uygun olarak düzenler. Bu yaklaşım, yapılandırma, önbellek ve durum dosyalarını yönetmek için temiz ve standart bir yol sunar.

## Desteklenen ortam değişkenleri {#supported-environment-variables}

Tuist hem standart XDG değişkenlerini hem de Tuist’e özel ön ekli varyantları destekler. Tuist’e özel varyantlar (`TUIST_` ön ekiyle) önceliklidir; böylece Tuist’i diğer uygulamalardan bağımsız olarak yapılandırabilirsiniz.

### Yapılandırma dizini {#configuration-directory}

**Ortam değişkenleri:**
- `TUIST_XDG_CONFIG_HOME` (önceliklidir)
- `XDG_CONFIG_HOME`

**Varsayılan:** `~/.config/tuist`

**Kullanım alanı:**
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

**Kullanım alanı:**
- **Eklentiler**: İndirilen ve derlenen eklenti önbelleği
- **ProjectDescriptionHelpers**: Derlenmiş proje açıklama yardımcıları
- **Bildirimler**: Önbelleğe alınmış bildirim dosyaları
- **Projeler**: Oluşturulan otomasyon projesi önbelleği
- **EditProjects**: edit komutu için önbellek
- **Çalıştırmalar**: Test ve derleme çalıştırma analiz verileri
- **İkili Dosyalar**: Derleme çıktı ikili dosyaları (ortamlar arasında paylaşılamaz)
- **SelectiveTests**: Seçici test önbelleği

**Örnek:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Durum dizini {#state-directory}

**Ortam değişkenleri:**
- `TUIST_XDG_STATE_HOME` (önceliklidir)
- `XDG_STATE_HOME`

**Varsayılan:** `~/.local/state/tuist`

**Kullanım alanı:**
- **Oturumlar**: Oturum günlükleri ve ağ kayıtları (`sessions/{uuid}/`)
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

Hangi dizinin kullanılacağını belirlerken Tuist, ortam değişkenlerini aşağıdaki sırayla kontrol eder:

1. **Tuist’e özel değişken** (ör. `TUIST_XDG_CONFIG_HOME`)
2. **Standart XDG değişkeni** (ör. `XDG_CONFIG_HOME`)
3. **Varsayılan konum** (ör. `~/.config/tuist`)

Bu sayede şunları yapabilirsiniz:
- Tüm uygulamalarınızı tutarlı bir şekilde düzenlemek için standart XDG değişkenlerini kullanın
- Tuist için farklı konumlara ihtiyaç duyduğunuzda Tuist’e özel değişkenlerle geçersiz kılın
- Herhangi bir yapılandırma yapmadan mantıklı varsayılanlara güvenin

## Yaygın kullanım senaryoları {#common-use-cases}

### Tuist’i proje başına izole etme {#isolating-tuist-per-project}

Tuist’in önbelleğini ve durumunu proje başına izole etmek isteyebilirsiniz:

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

### İzole dizinlerle hata ayıklama {#debugging-with-isolated-directories}

Sorunları hata ayıklarken temiz bir başlangıç yapmak isteyebilirsiniz:

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
