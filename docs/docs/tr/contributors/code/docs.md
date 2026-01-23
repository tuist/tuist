---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Belgeler {#docs}

Kaynak:
[github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## Ne için kullanılır? {#what-it-is-for}

Doküman sitesi, Tuist'in ürün ve katkıcı dokümantasyonunu barındırır. VitePress
ile oluşturulmuştur.

## Nasıl katkıda bulunabilirsiniz? {#how-to-contribute}

### Yerel olarak ayarlayın {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### İsteğe bağlı oluşturulan veriler {#optional-generated-data}

Belgelere bazı oluşturulmuş veriler ekliyoruz:

- CLI referans verileri: `mise run generate-cli-docs`
- Proje manifestosu referans verileri: `mise run generate-manifests-docs`

Bunlar isteğe bağlıdır. Belgeler bunlar olmadan da görüntülenir, bu nedenle
yalnızca oluşturulan içeriği yenilemeniz gerektiğinde bunları çalıştırın.
