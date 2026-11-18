---
{
  "title": "Xcode Derleme İçgörüleri",
  "titleTemplate": ":title · Derleme İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Yerel ve CI derleme performansını izlemek için Tuist panosunda Xcode derleme analizlerini takip edin."
}
---
# Xcode derleme içgörüleri {#xcode-build-insights}

Büyük projeler üzerinde çalışırken aynı kodu tekrar tekrar derlemek gerekmemelidir. Tuist Build Insights, yerel ve CI derleme süreleri darboğaz haline gelmeden önce eğilimleri belirlemenizi sağlayan derleme analitiğini izlemenize olanak tanır.

Derleme içgörüleri, genellikle şemanızın post-action adımına eklenen `tuist inspect build` komutu tarafından sağlanır.

Yerel derleme sürelerini izlemeye başlamak için, şemanızın post-action adımına `tuist inspect build` komutunu ekleyerek bu komuttan yararlanabilirsiniz:

![Derlemeleri incelemek için post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Derleme yapılandırmasını yakalamak için "Provide build settings from" alanını yürütülebilir dosyaya veya ana derleme hedefinize ayarlayın.

> [!NOTE]
> Derleme başarısız olduğunda post-scheme eylemi çalıştırılmaz.
>
> Bu durumda, şemanın `.xcscheme` dosyasındaki `<BuildAction>` öğesinde `runPostActionsOnFailure` değerini `YES` olarak ayarlayarak bunu çalıştırabilirsiniz:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

[Mise](https://mise.jdx.dev/) için, post-action ortamında `tuist` etkinleştirin:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise yol çözümlemesi**
>
> Ortamınızın `PATH` değeri şema post-action tarafından devralınmaz, bu nedenle Mise'nin mutlak yolunu kullanın. Bu, Mise'yi nasıl yüklediğinize bağlıdır. Derleme ayarları bir hedeften devralınmalıdır, böylece `mise` `$SRCROOT` konumundan çalışabilir.

[Homebrew](https://brew.sh/) için, Homebrew yollarını post-action ortamına ekleyin:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Giriş yaptıktan sonra, yerel derlemeler izlenir ve Tuist kontrol panelinden erişilebilir:

> [!TIP]
> Kontrol paneline hızlıca erişmek için CLI'dan `tuist project show --web` komutunu çalıştırın.

![Derleme içgörülerini içeren kontrol paneli](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
