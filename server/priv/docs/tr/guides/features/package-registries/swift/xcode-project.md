---
{
  "title": "Xcode projesi",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'yi bir Xcode projesinde nasıl kullanacağınızı öğrenin."
}
---
# Xcode projesi {#xcode-project}

Xcode projenizde kayıt defterini kullanarak paket eklemek için varsayılan Xcode kullanıcı arayüzünü kullanın. Xcode'da `Package Dependencies` sekmesindeki `+` düğmesine tıklayarak kayıt defterinde paketleri arayabilirsiniz. Paket kayıt defterinde mevcutsa, sağ üst köşede `tuist.dev` kayıt defterini görürsünüz:

![Paket bağımlılıkları ekleme](/images/guides/features/build/registry/registry-add-package.png)

## Kaynak kontrol paketlerini çözümleme {#resolving-source-control-packages}

Eklediğiniz paketlerin geçişli bağımlılıkları gibi, bir kaynak kontrol URL'si ile bildirilen paketler varsayılan olarak kaynak kontrolden çözülür. `tuist registry setup`, aşağıdaki kullanıcı varsayılanını yazarak Xcode'u bunları bunun yerine kayıt defterinden çözümleyecek şekilde yapılandırır:

```bash
defaults write com.apple.dt.Xcode IDEPackageDependencySCMToRegistryTransformation useRegistryIdentityAndSources
```

Xcode daha sonra, bir kayıt defteri eşdeğeri mevcut olduğunda kaynak kontrol paketini kayıt defterinden çözümler ve mevcut olmadığında kaynak kontrole geri döner.

> [!NOTE]
> Bu, makine başına bir Xcode tercihidir ve proje ayarı değildir; bu nedenle kayıt defteri yapılandırma dosyasını commitlemek onu ekibinizin geri kalanıyla paylaşmaz. Her geliştiricinin makinesinde bir kez `tuist registry setup` komutunu çalıştırması gerekir. Tercih daha sonra o makinedeki tüm Xcode projelerine uygulanır.
