---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Model Bağlam Protokolü (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com), LLM'lerin geliştirme
ortamlarıyla etkileşime girmesi için [Claude](https://claude.ai) tarafından
önerilen bir standarttır. Bunu LLM'lerin USB-C'si olarak düşünebilirsiniz. Kargo
ve taşımacılığı daha birlikte çalışabilir hale getiren nakliye konteynerleri
veya uygulama katmanını taşıma katmanından ayıran TCP gibi protokoller gibi MCP
de [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code) gibi LLM destekli
uygulamaları ve [Zed](https://zed.dev), [Cursor](https://www.cursor.com) veya
[VS Code](https://code.visualstudio.com) gibi editörleri diğer alanlarla
birlikte çalışabilir hale getirir.

Tuist, **uygulama geliştirme ortamınız** ile etkileşime girebilmeniz için CLI
aracılığıyla yerel bir sunucu sağlar. İstemci uygulamalarınızı buna bağlayarak,
projelerinizle etkileşim kurmak için dili kullanabilirsiniz.

Bu sayfada nasıl kurulacağını ve yeteneklerini öğreneceksiniz.

::: info
<!-- -->
Tuist MCP sunucusu, etkileşim kurmak istediğiniz projeler için Xcode'un en son
projelerini doğruluk kaynağı olarak kullanır.
<!-- -->
:::

## Kurun

Tuist, popüler MCP uyumlu istemciler için otomatik kurulum komutları sağlar.
İstemciniz için uygun komutu çalıştırmanız yeterlidir:

### [Claude](https://claude.ai)

Claude desktop](https://claude.ai/download) için çalıştırın:
```bash
tuist mcp setup claude
```

Bu, `~/Library/Application Support/Claude/claude_desktop_config.json`
adresindeki dosyayı yapılandıracaktır.

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Claude Code için çalıştırın:
```bash
tuist mcp setup claude-code
```

Bu, Claude masaüstü ile aynı dosyayı yapılandıracaktır.

### [İmleç](https://www.cursor.com)

Cursor IDE için bunu global veya yerel olarak yapılandırabilirsiniz:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Zed editörü için bunu global veya yerel olarak da yapılandırabilirsiniz:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Kodu](https://code.visualstudio.com)

MCP uzantılı VS Code için, global veya yerel olarak yapılandırın:
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

Aşağıdaki bölümlerde Tuist MCP sunucusunun yetenekleri hakkında bilgi
edineceksiniz.

### Kaynaklar

#### Son projeler ve çalışma alanları

Tuist, son zamanlarda çalıştığınız Xcode projelerinin ve çalışma alanlarının
kaydını tutar ve uygulamanıza güçlü içgörüler için bağımlılık grafiklerine
erişim sağlar. Proje yapınız ve ilişkileriniz hakkındaki ayrıntıları ortaya
çıkarmak için bu verileri sorgulayabilirsiniz:

- Belirli bir hedefin doğrudan ve geçişli bağımlılıkları nelerdir?
- Hangi hedef en çok kaynak dosyaya sahip ve kaç tane içeriyor?
- Grafikteki tüm statik ürünler (örn. statik kütüphaneler veya çerçeveler)
  nelerdir?
- Tüm hedefleri, adları ve ürün türleriyle (ör. uygulama, çerçeve, birim testi)
  birlikte alfabetik olarak sıralayarak listeleyebilir misiniz?
- Hangi hedefler belirli bir çerçeveye veya dış bağımlılığa bağlıdır?
- Projedeki tüm hedeflerdeki toplam kaynak dosya sayısı nedir?
- Hedefler arasında döngüsel bağımlılıklar var mı ve varsa nerede?
- Hangi hedefler belirli bir kaynağı (örneğin, bir görüntü veya plist dosyası)
  kullanıyor?
- Grafikteki en derin bağımlılık zinciri nedir ve hangi hedefler buna dahildir?
- Bana tüm test hedeflerini ve bunlarla ilişkili uygulama veya çerçeve
  hedeflerini gösterebilir misiniz?
- Son etkileşimlere göre hangi hedefler en uzun inşa sürelerine sahip?
- İki özel hedef arasındaki bağımlılık farklılıkları nelerdir?
- Projede kullanılmayan kaynak dosyaları veya kaynaklar var mı?
- Hangi hedefler ortak bağımlılıkları paylaşır ve bunlar nelerdir?

Tuist ile Xcode projelerinizi daha önce hiç olmadığı kadar derinlemesine
inceleyebilir, en karmaşık kurulumları bile anlamayı, optimize etmeyi ve
yönetmeyi kolaylaştırabilirsiniz!
