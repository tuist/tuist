---
{
  "title": "Yetenekler",
  "titleTemplate": ":title · Agent tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Kodlama ajanlarının proje geçişi gibi yaygın Tuist görevlerini gerçekleştirmek için kullanabileceği önceden hazırlanmış yetenekler."
}
---

# Yetenekler

Yetenekler, karmaşık ve çok adımlı Tuist görevlerini gerçekleştirmek için önceden hazırlanmış talimat setleridir. Bir taşıma veya kurulum sürecinde bir aracıyı manuel olarak yönlendirmek yerine, bir yetenek yükleyip işi aracıya bırakabilirsiniz.

Kodlama aracınız eklentileri destekliyorsa, <.localized_link href="/guides/features/agentic-coding/plugins">Tuist eklentileri</.localized_link> bu yetenekleri ve barındırılan Model Context Protocol sunucusunu birlikte yükler.

## Mevcut yetenekler

| Yetenek | Açıklama |
| --- | --- |
| `migrate` | Mevcut Xcode projelerini, derleme ve çalıştırma doğrulaması, harici bağımlılık eşlemesi ve taşıma kontrol listeleriyle Tuist tarafından oluşturulan çalışma alanlarına taşır. |
| `generated-projects` | Tuist tarafından oluşturulan çalışma alanlarında günlük çalışmaları yönlendirir: oluşturma, derleme/test komutları ve derlenebilir klasörler. |
| `fix-flaky-tests` | Tuist test içgörülerinden hata desenlerini analiz ederek, kök nedenleri belirleyerek ve hedefe yönelik düzeltmeler uygulayarak kararsız testleri giderir. |
| `debug-generated-project` | Senaryoyu yeniden oluşturarak, gerektiğinde Tuist'i kaynaktan derleyerek ve sorunun bir hata, hatalı yapılandırma mı yoksa ekip girdisi gerektiren bir durum mu olduğunu sınıflandırarak Tuist tarafından oluşturulan projelerle ilgili sorunları ayıklar. |
| `compare-gradle-builds` | Süre gerilemelerini, önbellek değişikliklerini ve görev sonucu farklarını belirlemek için iki Gradle derleme çalışmasını karşılaştırır. Derleme kimlikleri, kontrol paneli URL'leri veya dal adlarıyla çağrılabilir. |

## Kurulum {#installation}

Tuist yeteneklerini kurmanın önerilen yolu [`skills`](https://github.com/vercel-labs/skills) CLI'sını kullanmaktır. Kodlama ajanlarınızı otomatik olarak algılar ve `SKILL.md` dosyalarını doğru konuma yerleştirir.

### Tüm yetenekleri yükle

```bash
npx skills add tuist/agent-skills
```

Etkileşimli istem, hangi yeteneklerin ve ajanların kurulacağını seçmenizi sağlar.

### Belirli bir yeteneği yükle

```bash
npx skills add tuist/agent-skills --skill migrate
```

### Belirli bir ajan için yükle

```bash
npx skills add tuist/agent-skills -a claude-code
```

### Genel olarak yükle

Yetenekleri tüm projelerde kullanılabilir kılmak üzere ana dizininize yüklemek için `-g` bayrağını ekleyin:

```bash
npx skills add tuist/agent-skills -g
```

### Yetenekleri güncelle

```bash
npx skills update
```

### Etkileşimsiz (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### Manuel kurulum {#manual}

`skills` CLI'sını kullanmamayı tercih ediyorsanız, `SKILL.md` dosyalarını doğrudan indirebilirsiniz. İstediğiniz yetenek için değişkenleri ayarlayın ve ajanınız için `curl` komutunu çalıştırın:

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
