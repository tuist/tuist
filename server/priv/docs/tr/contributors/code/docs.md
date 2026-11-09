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

Dokümantasyon sitesi, Tuist’in ürün ve katkıda bulunanlar için hazırlanmış dokümanlarını barındırır. Tuist sunucusunun bir parçası olan bu Phoenix uygulaması, `server/priv/docs/en` altındaki Markdown sayfalarını `/docs` adresinde render eder.

## Nasıl katkıda bulunulur {#how-to-contribute}

`server/priv/docs/en` altındaki İngilizce sayfaları düzenleyin. Çeviriler ayrı olarak yönetildiğinden diğer yerel dizinleri düzenlemeyin. Yan menü `server/lib/tuist/docs_sidebar.ex` içinde tanımlanır; okuyucuların yeni sayfaları bulabilmesi için onları buraya ekleyin.

Birden fazla sayfa aynı metni paylaştığında, örneğin derleme sistemleri arasında aynı bölüm varsa, bu metni adı `_` ile başlayan bir dosyaya koyun ve kararsız testler sayfalarında olduğu gibi dosyayı işaret eden bir `@snippet:` HTML yorumuyla dahil edin. Adı `_` ile başlayan dosyalar tek başına sayfa olarak yayımlanmaz.

### Yerel kurulum {#set-up-locally}

Sunucuyu `server` dizininden, [kurulum talimatlarını](https://github.com/tuist/tuist/blob/main/server/AGENTS.md) izleyerek çalıştırın:

```bash
cd server
mise install
mise run dev
```

Ardından [http://localhost:8080/en/docs](http://localhost:8080/en/docs) adresini açın.

### Oluşturulan içerik {#generated-content}

CLI referansı, en son CLI sürümünün komut özelliklerinden otomatik olarak oluşturulur; bu nedenle yerel olarak derlenmesine gerek yoktur.

ProjectDescription API referansı, [projectdescription.tuist.dev](https://projectdescription.tuist.dev) adresinde ayrı bir DocC sitesi olarak barındırılır. Yerel olarak derlemek için depo kökünden `mise run docs:project-description` komutunu çalıştırın.
