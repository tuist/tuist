---
{
  "title": "Tuist'i Yükle",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "mise veya Homebrew kullanarak macOS ya da Linux üzerinde Tuist komut satırı arayüzünü yükleyin ve ekipler ile sürekli entegrasyon için bir sürümü sabitleyin."
}
---
# Tuist'i Yükle {#install-tuist}

Tuist komut satırı arayüzü **macOS** ve **Linux** üzerinde çalışır ve Xcode, oluşturulmuş, Gradle, Bazel ve Rust projelerinizi Tuist'in önbellek, analiz ve runner altyapısına bağlar. Tuist'i [kaynak kodundan](https://github.com/tuist/tuist) derleyebilirsiniz ancak geçerli ve doğrulanabilir bir kurulum sağlamak için aşağıdaki kurulum yöntemlerinden birini öneririz. Elixir projeleri bunun yerine `tuist_ex` Hex paketini kullanır ve CLI'ye ihtiyaç duymaz.

## Mise {#recommended-mise}

> [!NOTE]
> Mise yüklü değilse öncelikle [başlangıç kılavuzunu](https://mise.jdx.dev/getting-started.html) takip edin. Farklı ortamlarda araçların deterministik sürümlerini sağlamanız gereken bir ekip veya kuruluşsanız Mise, [Homebrew](https://brew.sh) için önerilen bir alternatiftir.


Homebrew gibi araçlar tek bir sürümü küresel olarak yükleyip etkinleştirirken **Mise bir sürümü sabitler**; bunu ya küresel düzeyde ya da proje kapsamına göre yapar. Tuist'i yüklemek ve etkinleştirmek için `mise use` komutunu çalıştırın:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

Zaten `mise.toml` içinde sabitlenmiş bir Tuist sürümüne sahip bir projeyi klonladıysanız yüklemek için `mise install` komutunu çalıştırın.

> [!TIP]
> `tuist@latest`, en son **kararlı** sürüme çözülür. Tuist ayrıca ön sürüm canary ve release candidate derlemelerini de yayınlar; bunlar yalnızca isteğe bağlıdır ve `latest` tarafından asla çözülmez. Güvenebileceğiniz kararlı bir hattı nasıl sabitleyeceğinizi ve ön sürümlere nasıl katılacağınızı öğrenmek için <.localized_link href="/cli/release/channels">Sürüm kanalları</.localized_link> sayfasına bakın.

<details>
<summary>Linux desteği</summary>

Linux'ta Tuist yalnızca Mise üzerinden kullanılabilir. Xcode'a bağımlı komutlar (`tuist generate` gibi) Linux'ta mevcut değildir ancak platformdan bağımsız komutlar (`tuist inspect bundle` gibi) beklendiği gibi çalışır.

</details>


## Homebrew (yalnızca macOS) {#recommended-homebrew}

Tuist'i [Homebrew](https://brew.sh) ve [formüllerimiz](https://github.com/tuist/homebrew-tuist) kullanarak yükleyebilirsiniz:

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
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP vekil sunucu {#http-proxy}

Ağınız giden trafiği bir HTTP vekil sunucu üzerinden yönlendiriyorsa <.localized_link href="/guides/integrations/http-proxy">HTTP vekil sunucu kılavuzuna</.localized_link> bakın.
