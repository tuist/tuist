---
{
  "title": "Eklentiler",
  "titleTemplate": ":title · Agent tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Cursor için Tuist eklentisini veya satıcıdan bağımsız Agent Eklentileri paketini yükleyin."
}
---

# Eklentiler

Tuist, agent yeteneklerini ve barındırılan MCP sunucusunu eklenti olarak paketler; böylece ikisini birlikte kurabilirsiniz. Kodlama agentinize uygun paketi seçin.

## Claude Code

[Tuist Claude Code marketplace](https://github.com/tuist/claude-plugin), Tuist eklentisini şu komutlarla kurulacak şekilde paketler:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

Bu eklenti Tuist yeteneklerini sağlar ve Claude Code'u barındırılan MCP sunucusuna bağlar.

## Cursor

[Tuist plugin for Cursor](https://github.com/tuist/cursor-plugin) eklentisini [Cursor Marketplace](https://cursor.com/marketplace) üzerinden kurun:

1. Cursor kenar çubuğunda **Customize** seçeneğini açın.
2. **Tuist** araması yapın.
3. **Install** seçeneğini belirleyin, ardından eklentiyi mevcut proje için mi yoksa kullanıcı hesabınız için mi kuracağınızı seçin.

Aynı kurulum akışını açmak için Cursor'da `/add-plugin` yazabilirsiniz. Bu eklenti Tuist yeteneklerini sağlar ve Cursor'u barındırılan MCP sunucusuna bağlar.

Kuruluşunuz Cursor marketplacesini yönetiyorsa, önce `https://github.com/tuist/cursor-plugin` adresini **Settings → Plugins → Team Marketplaces → Import Marketplace** yolundan içe aktarın.

## Diğer kodlama agentleri

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin), açık ve satıcıdan bağımsız [Agent Plugins](https://agent-plugins.org/) standardını takip eder. Uygun bir istemciyi, o istemcinin eklenti dizinlerini kurma veya referans gösterme talimatlarına uyarak depoya yönlendirin:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

Bu işlem Tuist yeteneklerini kurar ve `https://tuist.dev/mcp` adresini uzak bir MCP sunucusu olarak kaydeder. Henüz Agent Plugins desteği olmayan istemciler için <.localized_link href="/guides/features/agentic-coding/skills">yetkinlikleri</.localized_link> ayrı ayrı kurun veya <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> ayrı yapılandırın.

## Kimlik Doğrulama

Çoğu yetkinlik Tuist komut satırı arayüzünü kullanır; bu nedenle bir agentin proje verilerinize erişmesini istemeden önce arayüzü bir kez kimlik doğrulamasından geçirin:

```bash
tuist auth login
```

Barındırılan MCP sunucusu gerektiğinde kendi oturum açma işlemini talep eder. İstemciye özel kurulum ve kimlik doğrulama ayrıntıları için <.localized_link href="/guides/features/agentic-coding/mcp">MCP kılavuzuna</.localized_link> bakın.
