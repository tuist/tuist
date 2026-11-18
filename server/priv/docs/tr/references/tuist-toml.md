---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · Referanslar · Tuist",
  "description": "tuist.toml yapılandırma dosyası biçimi için referans."
}
---

# tuist.toml {#tuist-toml}

`tuist.toml`, derleme sistemi bağımsız bir yapılandırma dosyasıdır ve `Tuist.swift`’nin evrimidir. `Tuist.swift`’den farklı olarak Swift gerektirmez, bu da onu herhangi bir platformda ve derleme sisteminde kullanılabilir hale getirir. Linux tabanlı CI çalıştırıcıları gibi Swift’in mevcut olmadığı ortamlar veya tam bir `Tuist.swift` bildirimine gerek duymadan yalnızca sunucuyla ilgili ayarları yapılandırmanız gerektiğinde idealdir.

Tuist, `tuist.toml` dosyasını geçerli çalışma dizininden yukarı doğru dizin hiyerarşisini tarayarak arar ve ilk eşleşmede durur. Bu, dosyayı projenizin kök dizinine yerleştirebileceğiniz ve Tuist komutlarını herhangi bir alt dizinden çalıştırabileceğiniz anlamına gelir.

## Desteklenen anahtarlar {#supported-keys}

| Anahtar | Tür | Zorunlu | Varsayılan | Açıklama |
| --- | --- | --- | --- | --- |
| `project` | `String` | Evet | — | Projenizin tam tanıtıcısı (ör. `"tuist/tuist"`). |
| `url` | `String` | Hayır | `https://tuist.dev` | Tuist sunucusunun URL’si. |

### Ağ {#network}

`[network]` tablosu, Tuist’in giden HTTP bağlantılarını nasıl kurduğunu yapılandırır.

| Anahtar | Tür | Zorunlu | Varsayılan | Açıklama |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | Hayır | `true` | `true` olduğunda, Tuist varsa `HTTPS_PROXY`/`HTTP_PROXY` ile tanımlanan proxy’yi kullanır. <.localized_link href="/guides/integrations/http-proxy">HTTP proxy kılavuzuna</.localized_link> bakın. |
| `ca_certificate` | `String` | Hayır | — | Sistem kök deposunun üzerine güvenilecek PEM veya DER CA sertifikası paketinin yolu; örneğin özel bir CA kullanan kendi barındırdığınız bir sunucu için. `TUIST_CA_CERTIFICATE` ortam değişkeni önceliklidir. <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">Özel bir CA sertifikasına güvenme</.localized_link> bölümüne bakın. |

## Örnek {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## Yapılandırma önceliği {#configuration-precedence}

Aynı ayar birden fazla yerde tanımlandığında, Tuist bunu aşağıdaki öncelik sırasına göre çözümler (yüksekten düşüğe):

1. **CLI bayrakları**
2. **Ortam değişkenleri**
3. **Tuist.swift**
4. **tuist.toml**
5. **Varsayılanlar**
