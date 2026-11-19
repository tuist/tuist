---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · Referanslar · Tuist",
  "description": "tuist.toml yapılandırma dosyası biçimi referansı."
}
---

# tuist.toml {#tuist-toml}

`tuist.toml`, derleme sisteminden bağımsız bir yapılandırma dosyasıdır ve `Tuist.swift` dosyasının evrimleşmiş halidir. `Tuist.swift` dosyasının aksine Swift gerektirmez, bu da onu herhangi bir platformda ve derleme sisteminde kullanılabilir kılar. Swift’in bulunmadığı ortamlar (örneğin Linux tabanlı CI çalıştırıcıları) veya tam bir `Tuist.swift` bildirimine ihtiyaç duymadan yalnızca sunucuyla ilgili ayarları yapılandırmak istediğiniz durumlar için idealdir.

Tuist, `tuist.toml` dosyasını mevcut çalışma dizininden başlayarak dizin hiyerarşisini yukarı doğru tarayarak arar ve ilk eşleşmede durur. Bu, dosyayı projenizin kök dizinine yerleştirip Tuist komutlarını herhangi bir alt dizinden çalıştırabileceğiniz anlamına gelir.

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
