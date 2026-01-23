---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Kaynak:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
ve
[github.com/tuist/tuist/tree/main/CLI](https://github.com/tuist/tuist/tree/main/cli)

## Ne için kullanılır? {#what-it-is-for}

CLI, Tuist'in kalbidir. Proje oluşturma, otomasyon iş akışları (test,
çalıştırma, grafik ve inceleme) işlemlerini gerçekleştirir ve kimlik doğrulama,
önbellek, içgörüler, önizlemeler, Kayıt ve seçmeli testler gibi özellikler için
Tuist sunucusuna arayüz sağlar.

## Nasıl katkıda bulunabilirsiniz? {#how-to-contribute}

### Gereksinimler {#requirements}

- macOS 14.0+
- Xcode 26+

### Yerel olarak ayarlayın {#set-up-locally}

- Depoyu klonlayın: `git clone git@github.com:tuist/tuist.git`
- Mise'yi [resmi kurulum komut
  dosyasını](https://mise.jdx.dev/getting-started.html) (Homebrew değil)
  kullanarak kurun ve `mise install komutunu çalıştırın.`
- Tuist bağımlılıklarını yükleyin: `tuist install`
- Çalışma alanını oluşturun: `tuist generate`

Oluşturulmuş proje otomatik olarak açılır. Daha sonra yeniden açmanız gerekirse,
`open Tuist.xcworkspace` komutunu çalıştırın.

::: info XED .
<!-- -->
`xed.` kullanarak projeyi açmaya çalışırsanız, Tuist tarafından oluşturulan
çalışma alanı değil, paket açılır. `Tuist.xcworkspace` kullanın.
<!-- -->
:::

### Tuist'i çalıştırın {#run-tuist}

#### Xcode'dan {#from-xcode}

`tuist` şemasını düzenleyin ve `generate --no-open` gibi argümanları ayarlayın.
Çalışma dizinini proje kök dizinine ayarlayın (veya `--path` kullanın).

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
CLI, `ProjectDescription` dosyasının oluşturulmasına bağlıdır. Çalışmazsa, önce
`Tuist-Workspace` şemasını oluşturun.
<!-- -->
:::

#### Terminalden {#from-the-terminal}

Önce çalışma alanını oluşturun:

```bash
tuist generate --no-open
```

Ardından, Xcode ile `tuist` yürütülebilir dosyasını oluşturun ve DerivedData'dan
çalıştırın:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

Veya Swift paketi Yöneticisi aracılığıyla:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
