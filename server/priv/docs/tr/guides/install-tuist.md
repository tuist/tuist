---
{
  "title": "Tuist'i Kurun",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "mise veya Homebrew kullanarak Tuist komut satırı arayüzünü macOS veya Linux üzerine kurun ve ekipler ile sürekli entegrasyon için bir sürümü sabitleyin."
}
---
# Tuist'i Kurun {#install-tuist}

Tuist komut satırı arayüzü **macOS** ve **Linux** üzerinde çalışır ve Xcode, oluşturulmuş, Gradle, Bazel ve Rust projelerinizi Tuist'in önbellek, analiz ve çalıştırıcı altyapısına bağlar. Tuist'i [kaynak koddan](https://github.com/tuist/tuist) derleyebilirsiniz ancak geçerli ve doğrulanabilir bir kurulum sağlamak için aşağıdaki kurulum yöntemlerinden birini öneririz. Elixir projeleri bunun yerine `tuist_ex` Hex paketini kullanır ve CLI'ye ihtiyaç duymaz.

## Mise {#recommended-mise}

> [!NOTE]
> Mise yüklü değilse öncelikle [başlangıç kılavuzunu](https://mise.jdx.dev/getting-started.html) izleyin. Farklı ortamlarda araçların deterministik sürümlerini sağlamanız gereken bir ekip veya kuruluşsanız Mise, [Homebrew](https://brew.sh) için önerilen bir alternatiftir.


Homebrew gibi araçlar tek bir sürümü küresel olarak yükler ve etkinleştirirken **Mise bir sürümü sabitler**; bu sabitleme ya küresel düzeyde ya da proje kapsamında yapılır. Tuist'i yüklemek ve etkinleştirmek için `mise use` komutunu çalıştırın:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Zaten `mise.toml` içinde sabitlenmiş bir Tuist sürümüne sahip bir projeyi klonlarsanız onu yüklemek için `mise install` komutunu çalıştırın.

> [!TIP]
> `tuist@latest`, en son **kararlı** sürüme çözülür. Tuist ayrıca ön sürüm canary ve release candidate yapılarını da yayımlar; bunlar yalnızca isteğe bağlıdır ve `latest` tarafından asla çözülmez. Güvenebileceğiniz kararlı bir hattı nasıl sabitleyeceğinizi ve ön sürümlere nasıl katılacağınızı öğrenmek için <.localized_link href="/cli/release/channels">Sürüm kanalları</.localized_link> sayfasına bakın.

<details>
<summary>Linux desteği</summary>

Linux'ta Tuist yalnızca Mise üzerinden kullanılabilir. Xcode'a bağımlı komutlar (örneğin `tuist generate`) Linux'ta mevcut değildir ancak `tuist inspect bundle` gibi platformdan bağımsız komutlar beklendiği gibi çalışır.

</details>


## Homebrew (yalnızca macOS) {#recommended-homebrew}

Tuist'i [Homebrew](https://brew.sh) ve [formüllerimiz](https://github.com/tuist/homebrew-tuist) kullanarak kurabilirsiniz:

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **İkili dosyaların özgünlüğünü doğrulama**
>
> Aşağıdaki komutu çalıştırarak kurulumunuzdaki ikili dosyaların bizim tarafımızdan derlendiğini doğrulayabilirsiniz; bu komut sertifikanın takım kimliğinin `U6LC622NKF` olup olmadığını kontrol eder:
>
> ```bash
> curl -fsSL "https://tuist.dev/verify.sh" | bash
> ```

## HTTP vekil sunucusu {#http-proxy}

Ağınız giden trafiği bir HTTP vekil sunucusu üzerinden yönlendiriyorsa <.localized_link href="/guides/integrations/http-proxy">HTTP vekil sunucusu kılavuzuna</.localized_link> bakın.

## Sonraki adımlar {#next-steps}

- Projenizi Tuist'e bağlamak için <.localized_link href="/guides/get-started">Başlangıç kılavuzunu</.localized_link> izleyin.
- Daha geniş ürün bağlamı için [mühendislik ekipleri ve kodlama ajanları için Tuist derleme altyapısını](https://tuist.dev) keşfedin.
