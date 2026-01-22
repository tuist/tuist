---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Model Bağlam Protokolü (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com),
[Claude](https://claude.ai) tarafından LLM'lerin geliştirme ortamlarıyla
etkileşime girmesi için önerilen bir standarttır. Bunu LLM'lerin USB-C'si olarak
düşünebilirsiniz. Kargo ve taşımacılığı daha uyumlu hale getiren nakliye
konteynerleri veya uygulama katmanını taşıma katmanından ayıran TCP gibi
protokoller gibi, MCP de [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code) gibi LLM destekli
uygulamaları ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya
[VS Code](https://code.visualstudio.com) gibi editörleri diğer alanlarla uyumlu
hale getirir.

Tuist, CLI aracılığıyla yerel bir sunucu sağlar, böylece **uygulama geliştirme
ortamınızla etkileşim kurabilirsiniz**. İstemci uygulamalarınızı buna
bağlayarak, dil kullanarak projelerinizle etkileşim kurabilirsiniz.

Bu sayfada, nasıl kurulacağı ve özellikleri hakkında bilgi edineceksiniz.

::: info
<!-- -->
Tuist MCP sunucusu, etkileşim kurmak istediğiniz projeler için Xcode'un en son
projelerini doğru kaynak olarak kullanır.
<!-- -->
:::

## Ayarlar

Tuist, popüler MCP uyumlu istemciler için otomatik kurulum komutları sağlar.
İstemciniz için uygun komutu çalıştırmanız yeterlidir:

### [Claude](https://claude.ai)

[Claude desktop](https://claude.ai/download) için şunu çalıştırın:
```bash
tuist mcp setup claude
```

Bu, `~/Library/Application Support/Claude/claude_desktop_config.json` dosyasını
yapılandıracaktır.

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Claude Code için şunu çalıştırın:
```bash
tuist mcp setup claude-code
```

Bu, Claude masaüstü ile aynı dosyayı yapılandıracaktır.

### [İmleç](https://www.cursor.com)

Cursor IDE için, bunu genel veya yerel olarak yapılandırabilirsiniz:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Zed editörü için, bunu genel veya yerel olarak da yapılandırabilirsiniz:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

MCP uzantısı olan VS Code için, bunu global veya lokal olarak yapılandırın:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Manuel Yapılandırma

Manuel olarak yapılandırmayı tercih ediyorsanız veya farklı bir MCP istemcisi
kullanıyorsanız, Tuist MCP sunucusunu istemcinizin yapılandırmasına ekleyin:

::: code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## Yetenekler

Aşağıdaki bölümlerde Tuist MCP sunucusunun özellikleri hakkında bilgi
edineceksiniz.

### Kaynaklar

#### Son projeler ve çalışma alanları

Tuist, son zamanlarda çalıştığınız Xcode projeleri ve çalışma alanlarının
kaydını tutar ve uygulamanıza güçlü içgörüler için bunların bağımlılık
grafiklerine erişim sağlar. Bu verileri sorgulayarak proje yapınız ve
ilişkileriniz hakkında ayrıntıları ortaya çıkarabilirsiniz, örneğin:

- Belirli bir hedefin doğrudan ve geçişli bağımlılıkları nelerdir?
- Hangi hedef en fazla kaynak dosyasına sahiptir ve kaç tane içerir?
- Grafikteki tüm statik ürünler (ör. statik kütüphaneler veya çerçeveler)
  nelerdir?
- Tüm hedefleri alfabetik sırayla, adları ve ürün türleri (ör. uygulama,
  çerçeve, birim testi) ile birlikte listeleyebilir misiniz?
- Hangi hedefler belirli bir çerçeveye veya harici bağımlılığa bağlıdır?
- Projedeki tüm hedefler için kaynak dosyaların toplam sayısı nedir?
- Hedefler arasında döngüsel bağımlılıklar var mı? Varsa, nerede?
- Hangi hedefler belirli bir kaynağı (ör. resim veya plist dosyası) kullanır?
- Grafikteki en derin bağımlılık zinciri nedir ve hangi hedefler dahildir?
- Bana tüm test hedeflerini ve bunlarla ilişkili uygulama veya çerçeve
  hedeflerini gösterebilir misiniz?
- Son etkileşimlere göre en uzun derleme sürelerine sahip hedefler hangileridir?
- İki belirli hedef arasındaki bağımlılık farkları nelerdir?
- Projede kullanılmayan kaynak dosyaları veya kaynaklar var mı?
- Hangi hedefler ortak bağımlılıklara sahiptir ve bunlar nelerdir?

Tuist ile Xcode projelerinizi hiç olmadığı kadar derinlemesine inceleyebilir, en
karmaşık yapılandırmaları bile daha kolay anlayabilir, optimize edebilir ve
yönetebilirsiniz!
