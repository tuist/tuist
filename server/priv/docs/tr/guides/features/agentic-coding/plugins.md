---
{
  "title": "Eklentiler",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Cursor için Tuist eklentisini veya satıcıdan bağımsız Agent Plugins paketini yükleyin."
}
---

# Eklentiler

Tuist, agent yeteneklerini ve barındırılan MCP sunucusunu eklenti olarak paketler; böylece ikisini birlikte kurabilirsiniz. Kodlama agentinize uygun paketi seçin.

## Claude Code

[Tuist Claude Code pazar yeri](https://github.com/tuist/claude-plugin), Tuist eklentisini şu komutlarla kurulacak şekilde paketler:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

Eklenti, Tuist yeteneklerini sağlar ve Claude Code'u barındırılan MCP sunucusuna bağlar.

## Cursor

[Cursor Marketplace](https://cursor.com/marketplace) üzerinden [Cursor için Tuist eklentisini](https://github.com/tuist/cursor-plugin) kurun:

1. Cursor kenar çubuğunda **Özelleştir** öğesini açın.
2. **Tuist** araması yapın.
3. **Kur** seçeneğini belirleyin, ardından eklentiyi mevcut proje için mi yoksa kullanıcı hesabınız için mi kuracağınızı seçin.

Aynı kurulum akışını açmak için Cursor'da `/add-plugin` yazabilirsiniz. Eklenti, Tuist yeteneklerini sağlar ve Cursor'u barındırılan MCP sunucusuna bağlar.

Kuruluşunuz Cursor pazar yerlerini yönetiyorsa, önce **Ayarlar → Eklentiler → Takım Pazar Yerleri → Pazar Yerini İçe Aktar** yolundan `https://github.com/tuist/cursor-plugin` adresini içe aktarın.

## Diğer kodlama agentleri

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin), açık ve satıcıdan bağımsız [Agent Plugins](https://agent-plugins.org/) standardını takip eder. Uygun bir istemciyi, o istemcinin eklenti dizinlerini kurma veya referans verme talimatlarını izleyerek depoya yönlendirin:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

Tuist yeteneklerini kurar ve `https://tuist.dev/mcp` adresini uzak bir MCP sunucusu olarak kaydeder. Agent Plugins'i henüz desteklemeyen istemciler için <.localized_link href="/guides/features/agentic-coding/skills">yetkinlikleri</.localized_link> kurun veya <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> ayrı yapılandırın.

## Kimlik Doğrulama

Çoğu yetenek Tuist komut satırı arayüzünü kullanır; bu nedenle, bir agentin proje verilerinize erişmesini istemeden önce arayüzü bir kez kimlik doğrulayın:

```bash
tuist auth login
```

Barındırılan MCP sunucusu, gerektiğinde kendi oturum açma isteğini gönderir. İstemciye özel kurulum ve kimlik doğrulama ayrıntıları için <.localized_link href="/guides/features/agentic-coding/mcp">MCP kılavuzuna</.localized_link> bakın.
