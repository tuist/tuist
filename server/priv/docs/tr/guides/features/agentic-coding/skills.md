---
{
  "title": "Yetenekler",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Kodlama ajanlarının proje geçişi gibi yaygın Tuist görevlerini gerçekleştirmek için kullanabileceği hazır yetenekler."
}
---

# Beceriler

Beceriler, karmaşık ve çok adımlı Tuist görevlerini gerçekleştirmek için önceden hazırlanmış talimat setleridir. Bir agenti geçiş veya kurulum sürecinde manuel olarak yönlendirmek yerine, bir beceri yükleyip işi agentin halletmesini sağlayabilirsiniz.

Kodlama agentiniz eklentileri destekliyorsa, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentileri</.localized_link> bu becerileri ve barındırılan Model Context Protocol sunucusunu birlikte yükler.

## Mevcut beceriler

| Beceri | Açıklama |
| --- | --- |
| `migrate` | Mevcut Xcode projelerini, derleme ve çalıştırma doğrulaması, harici bağımlılık eşlemesi ve geçiş kontrol listeleriyle Tuist tarafından oluşturulan çalışma alanlarına geçirir. |
| `generated-projects` | Tuist tarafından oluşturulan çalışma alanlarında günlük çalışmayı yönlendirir: oluşturma, derleme/test komutları ve derlenebilir klasörler. |
| `fix-flaky-tests` | Tuist test içgörülerinden hata kalıplarını analiz ederek, kök nedenleri belirleyerek ve hedefe yönelik düzeltmeler uygulayarak kararsız testleri giderir. |
| `debug-generated-project` | Senaryoyu yeniden oluşturarak, gerektiğinde Tuist'i kaynaktan derleyerek ve sorunun bir hata, yanlış yapılandırma mı yoksa ekip girdisi gerektiren bir durum mu olduğunu sınıflandırarak Tuist tarafından oluşturulan projelerdeki sorunları hata ayıklar. |
| `compare-gradle-builds` | Süre gerilemelerini, önbellek değişikliklerini ve görev sonuç farklılıklarını belirlemek için iki Gradle derleme çalışmasını karşılaştırır. Derleme kimlikleri, kontrol paneli URL'leri veya dal adlarıyla çağrılabilir. |

## Kurulum {#installation}

Tuist becerilerini kurmanın önerilen yolu [`skills`](https://github.com/vercel-labs/skills) CLI'dir. Kodlama agentlerinizi otomatik olarak algılar ve `SKILL.md` dosyalarını doğru konuma yerleştirir.

### Tüm becerileri yükle

```bash
npx skills add tuist/agent-skills
```

Etkileşimli istem, hangi becerilerin ve agentlerin yükleneceğini seçmenizi sağlar.

### Belirli bir beceriyi yükle

```bash
npx skills add tuist/agent-skills --skill migrate
```

### Belirli bir agent için yükle

```bash
npx skills add tuist/agent-skills -a claude-code
```

### Global olarak yükle

Becerilerin tüm projelerde kullanılabilir olması için ana dizininize yüklemek üzere `-g` bayrağını ekleyin:

```bash
npx skills add tuist/agent-skills -g
```

### Becerileri güncelle

```bash
npx skills update
```

### Etkileşimsiz (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### Manuel kurulum {#manual}

`skills` CLI'yı kullanmamayı tercih ediyorsanız, `SKILL.md` dosyalarını doğrudan indirebilirsiniz. İstediğiniz beceri için değişkenleri ayarlayın ve agentiniz için `curl` komutunu çalıştırın:

```bash
SKILL_NAME=tuist-migrate          # or tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md  # or .../generated-projects/SKILL.md
```

::: code-group

```bash [Claude Code]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Codex]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Amp]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [OpenCode]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
