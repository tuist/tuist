## tuist share ile kanallar {#share-tracks}

`tuist share` ile yayınlama yapan iş akışlarında bir kanal seçmek için `--track` kullanın:

```bash
tuist share App --track beta
tuist share App --track nightly
```

## Sürüm notları {#release-notes}

Ortam grupları için kanalları, tek bir derlemenin amacı için sürüm notlarını kullanın:

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

`App` yerine uygulama adınızı, uygulama dosya yolunu veya çalıştırılabilir dağıtımınızı ve bunun `--executable` seçeneğini yazın. Sürüm notları isteğe bağlı düz metindir, en fazla 10.000 karakter olabilir. İlk boş olmayan satır önizleme listelerinde tek satırlık bir alıntı olarak görünür; böylece derleme numaraları ve diğer tanımlayıcı bilgiler ilk bakışta görülebilir. Uzun satırlar kısaltılır; tam notlar ayrıntı sayfalarında yer alır. Arama eşleşmeleri görünen adları ve alıntıda gösterilmeyen satırlar da dahil olmak üzere tüm sürüm notlarını kapsar. Çok satırlı notlar desteklenir, örneğin `--release-notes "$(< release-notes.txt)"`. Bunlar uygulamanın görünen adını veya kanalını değiştirmez.

### Uyumluluk {#preview-metadata-compatibility}

Sürüm notları bir derlemenin ait olduğu önizlemeyi değiştirmez. Bir önizlemenin aldığı ilk notlar saklanır: Daha sonraki bir yükleme, henüz notu olmayan bir önizlemeye not ekleyebilir ancak var olanları üzerine yazamaz veya temizleyemez. Sürüm notları özelliği bulunmadan önce yüklenen önizlemeler bunlar olmadan geçerliliğini korur.

Kendi sunucunuzda barındırılan dağıtımlar, sürüm notlarını ve kanal filtrelemeyi destekleyen bir sunucu sürümü ile güncel bir istemci gerektirir. Eski sunucular notları yoksayar. Liste uç noktalarının kanal ve arama filtreleri için [API referansına](https://tuist.dev/api/docs) bakın.

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">uzak projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.

Tuist projeniz Git platformunuzla bağlantılı hale geldiğinde, CI'da başarılı bir uygulama derlemesinden sonra <.localized_link href="/cli/share">`tuist share`</.localized_link> ekleyin. Tuist, önizleme bağlantısını doğrudan çekme/birleştirme isteklerinize gönderir; böylece inceleyenler yerel derleme yapmadan test edebilir:

![Tuist Önizleme bağlantısı içeren GitHub uygulama yorumu](/images/guides/features/github-app-with-preview.png)

## Otomasyonlar {#automations}

`tuist share` komutundan JSON çıktısı almak için `--json` kullanın:

```bash
tuist share --json
```

Sonucu, CI'dan Slack mesajı göndermek gibi özel otomasyonlarda kullanın. `url` anahtarı tam önizleme bağlantısını içerir; `qrCodeURL` ise önizlemeyi cihazda açmak için bir QR kodu görseline işaret eder:

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
