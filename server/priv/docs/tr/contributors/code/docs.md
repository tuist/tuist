---
{
  "title": "Dokümantasyon",
  "titleTemplate": ":title · Kod · Katkıda Bulunanlar · Tuist",
  "description": "Tuist dokümantasyon sitesine katkıda bulunun."
}
---
# Dokümanlar {#docs}

Kaynak: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## Ne işe yarar {#what-it-is-for}

Dokümantasyon sitesi, Tuist'in ürün ve katkıda bulunan dokümantasyonunu barındırır. Phoenix uygulaması olan Tuist sunucusunun bir parçasıdır ve Markdown sayfalarını `server/priv/docs/en` altında `/docs` adresinde render eder.

## Nasıl katkıda bulunulur {#how-to-contribute}

`server/priv/docs/en` altındaki İngilizce sayfaları düzenleyin. Çeviriler ayrı olarak yönetilir, bu nedenle diğer yerel dizinleri düzenlemeyin. Yan menü `server/lib/tuist/docs_sidebar.ex` içinde tanımlanır; okuyucuların bulabilmesi için yeni sayfaları buraya ekleyin.

Birden fazla sayfa aynı metni paylaştığında, örneğin derleme sistemleri genelinde aynı bölüm olduğunda, bu metni adı `_` ile başlayan ve bu sayfaların yanındaki bir dosyaya koyun ve kararsız testler sayfalarının yaptığı gibi, dosyayı işaret eden bir `@snippet:` HTML yorumu ile dahil edin. Adı `_` ile başlayan dosyalar tek başına sayfa olarak yayınlanmaz.

### Yerel kurulum {#set-up-locally}

Sunucuyu `server` dizininden, [kurulum talimatlarını](https://github.com/tuist/tuist/blob/main/server/AGENTS.md) izleyerek çalıştırın:

```bash
cd server
mise install
mise run dev
```

Ardından [http://localhost:8080/en/docs](http://localhost:8080/en/docs) adresini açın.

### Oluşturulan içerik {#generated-content}

CLI referansı, en son CLI sürümünün komut özelliklerinden oluşturulur, bu nedenle yerel olarak derlenmesine gerek yoktur.

ProjectDescription API referansı, [projectdescription.tuist.dev](https://projectdescription.tuist.dev) adresinde ayrı bir DocC sitesi olarak barındırılır. Yerel olarak derlemek için depo kökünden `mise run docs:project-description` komutunu çalıştırın.
