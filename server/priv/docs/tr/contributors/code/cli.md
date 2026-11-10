---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Tuist CLI'ye katkıda bulunun."
}
---
# CLI {#cli}

Kaynak: [github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist) ve [github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Ne işe yarar {#what-it-is-for}

CLI, Tuist’in kalbidir. Proje oluşturma, otomasyon iş akışlarını (test, çalıştırma, grafik ve inceleme) yönetir ve kimlik doğrulama, önbellek, içgörüler, önizlemeler, kayıt defteri ve seçici test gibi özellikler için Tuist sunucusuna arayüz sağlar.

## Nasıl katkıda bulunulur {#how-to-contribute}

### Gereksinimler {#requirements}

- macOS 14.0+
- Xcode 26+

### Yerel kurulum {#set-up-locally}

- Depoyu klonlayın: `git clone git@github.com:tuist/tuist.git`
- Mise’yi [resmi kurulum betiği](https://mise.jdx.dev/getting-started.html) ile (Homebrew değil) kurun ve `mise install` komutunu çalıştırın
- Tuist bağımlılıklarını yükleyin: `tuist install`
- Çalışma alanını oluşturun: `tuist generate`

Oluşturulan proje otomatik olarak açılır. Daha sonra yeniden açmanız gerekirse `open Tuist.xcworkspace` komutunu çalıştırın.

> [!NOTE]
> **`xed .`**
>
> Projeyi `xed .` kullanarak açmaya çalışırsanız, Tuist tarafından oluşturulan çalışma alanı yerine paketi açar. `Tuist.xcworkspace` kullanın.


### Tuist’i çalıştırma {#run-tuist}

#### Xcode’dan {#from-xcode}

`tuist` şemasını düzenleyin ve `generate --no-open` gibi argümanlar belirleyin. Çalışma dizinini proje köküne ayarlayın (veya `--path` kullanın).

> [!WARNING]
> **ProjectDescription derlemesi**
>
> CLI, `ProjectDescription` öğesinin derlenmesine bağlıdır. Çalıştırma başarısız olursa önce `Tuist-Workspace` şemasını derleyin.


#### Terminalden {#from-the-terminal}

Önce çalışma alanını oluşturun:

```bash
tuist generate --no-open
```

Ardından `tuist` yürütülebilir dosyasını Xcode ile derleyin ve DerivedData’dan çalıştırın:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

Veya Swift Package Manager üzerinden:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
