---
{
  "title": "Eklentiler",
  "titleTemplate": ":title · Ajan tabanlı kodlama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Cursor eklentisini veya satıcıdan bağımsız Agent Plugins paketini yükleyin."
}
---

# Eklentiler

Tuist, aracı yeteneklerini ve barındırılan MCP sunucusunu eklenti olarak paketler; böylece ikisini birlikte kurabilirsiniz. Kodlama aracınıza uygun paketi seçin.

## Claude Code

[Tuist Claude Code pazar yeri](https://github.com/tuist/claude-plugin), Tuist eklentisini şu komutlarla kurulacak şekilde paketler:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

Eklenti, Tuist yeteneklerini sağlar ve Claude Code'u barındırılan MCP sunucusuna bağlar.

## Cursor

[Cursor Pazar Yeri](https://cursor.com/marketplace)nden [Cursor için Tuist eklentisini](https://github.com/tuist/cursor-plugin) yükleyin:

1. Cursor kenar çubuğunda **Özelleştir** seçeneğini açın.
2. **Tuist** arayın.
3. **Yükle** seçeneğini belirleyin, ardından eklentiyi geçerli proje için mi yoksa kullanıcı hesabınız için mi yüklemek istediğinizi seçin.

Aynı kurulum akışını açmak için Cursor'da `/add-plugin` yazabilirsiniz. Eklenti, Tuist yeteneklerini sağlar ve Cursor'u barındırılan MCP sunucusuna bağlar.

Kuruluşunuz Cursor pazar yerlerini yönetiyorsa, öncelikle **Ayarlar → Eklentiler → Takım Pazar Yerleri → Pazar Yerini İçe Aktar** yolundan `https://github.com/tuist/cursor-plugin` adresini içe aktarın.

## Diğer kodlama ajanları

[Tuist Agent Plugin](https://github.com/tuist/agent-plugin), açık ve satıcıdan bağımsız [Agent Plugins](https://agent-plugins.org/) standardını takip eder. Uyumlu bir istemciyi, o istemcinin eklenti dizinlerini yükleme veya referans gösterme talimatlarını izleyerek depoya yönlendirin:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

Tuist yeteneklerini yükler ve `https://tuist.dev/mcp` adresini uzak bir MCP sunucusu olarak kaydeder. Henüz Agent Plugins'i desteklemeyen istemciler için <.localized_link href="/guides/features/agentic-coding/skills">yetenekleri</.localized_link> ayrı ayrı yükleyin veya <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusunu</.localized_link> ayrı yapılandırın.

## Kimlik Doğrulama

Çoğu yetenek Tuist komut satırı arayüzünü kullanır; bu nedenle, bir ajandan proje verilerinize erişmesini istemeden önce arayüzü bir kez kimlik doğrulamasından geçirin:

```bash
tuist auth login
```

Barındırılan MCP sunucusu, gerektiğinde kendi oturum açma isteğini gönderir. İstemciye özel kurulum ve kimlik doğrulama ayrıntıları için <.localized_link href="/guides/features/agentic-coding/mcp">MCP kılavuzuna</.localized_link> bakın.
