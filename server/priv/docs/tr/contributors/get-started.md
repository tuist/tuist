---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# Başlayın {#get-started}

Eğer iOS gibi Apple platformları için uygulama geliştirme deneyiminiz varsa,
Tuist'e kod eklemek çok da farklı olmayacaktır. Uygulama geliştirmeye kıyasla
bahsetmeye değer iki fark vardır:

- **CLI'lar ile etkileşimler terminal üzerinden gerçekleşir.** Kullanıcı,
  istenen görevi yerine getiren Tuist'i çalıştırır ve ardından başarılı bir
  şekilde veya bir durum koduyla geri döner. Yürütme sırasında, standart çıktı
  ve standart hataya çıktı bilgileri gönderilerek kullanıcı bilgilendirilebilir.
  Herhangi bir hareket ya da grafiksel etkileşim yoktur, sadece kullanıcının
  niyeti vardır.

- **Uygulama sistem veya kullanıcı olaylarını aldığında bir iOS uygulamasında
  olduğu gibi** girişini bekleyerek süreci canlı tutan bir runloop yoktur.
  CLI'lar kendi süreci içinde çalışır ve iş bittiğinde sona erer. Asenkron
  çalışma
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  veya [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency)
  gibi sistem API'leri kullanılarak yapılabilir, ancak asenkron çalışma
  yürütülürken sürecin çalıştığından emin olunması gerekir. Aksi takdirde, süreç
  eşzamansız çalışmayı sonlandıracaktır.

Swift ile herhangi bir deneyiminiz yoksa, dile ve Vakfın API'sinden en çok
kullanılan öğelere aşina olmak için [Apple'ın resmi
kitabı](https://docs.swift.org/swift-book/) öneriyoruz.

## Minimum gereksinimler {#minimum-requirements}

Tuist'e katkıda bulunmak için asgari şartlar şunlardır:

- macOS 14.0+
- Xcode 16.3+

## Projeyi yerel olarak kurun {#set-up-the-project-locally}

Proje üzerinde çalışmaya başlamak için aşağıdaki adımları takip edebiliriz:

- Şu adresi çalıştırarak depoyu klonlayın: `git clone
  git@github.com:tuist/tuist.git`
- [Yükle](https://mise.jdx.dev/getting-started.html) Geliştirme ortamını
  sağlamak için Mise.
- Tuist tarafından ihtiyaç duyulan sistem bağımlılıklarını yüklemek için `mise
  install` adresini çalıştırın
- Tuist tarafından ihtiyaç duyulan harici bağımlılıkları yüklemek için `tuist
  install` adresini çalıştırın
- (İsteğe bağlı) <LocalizedLink href="/guides/features/cache">Tuist Önbelleğine erişmek için `tuist auth login` adresini çalıştırın</LocalizedLink>
- Tuist'in kendisini kullanarak Tuist Xcode projesini oluşturmak için `tuist
  generate` adresini çalıştırın

**Oluşturulmuş projele otomatik olarak açılır**. Oluşturmadan tekrar açmanız
gerekirse, `çalıştırın Tuist.xcworkspace` açın (veya Finder'ı kullanın).

::: info XED .
<!-- -->
Projeyi `xed .` adresini kullanarak açmaya çalışırsanız, Tuist tarafından
oluşturulan projeyi değil, paketi açacaktır. Aracı beslemek için Tuist
tarafından oluşturulan projeyi kullanmanızı öneririz.
<!-- -->
:::

## Projeyi düzenleyin {#edit-the-project}

Projeyi düzenlemeniz gerekirse, örneğin bağımlılıklar eklemek veya hedefleri
ayarlamak için <LocalizedLink href="/guides/features/projects/editing">`tuist edit` komutunu</LocalizedLink> kullanabilirsiniz. Bu çok az kullanılır, ancak
var olduğunu bilmek iyidir.

## Run Tuist {#run-tuist}

### Xcode'dan {#from-xcode}

Oluşturulmuş Xcode projesinden `tuist` çalıştırmak için, `tuist` şemasını
düzenleyin ve komuta iletmek istediğiniz argümanları ayarlayın. Örneğin, `tuist
generate` komutunu çalıştırmak için, argümanları `generate --no-open` olarak
ayarlayarak projenin oluşturulduktan sonra açılmasını önleyebilirsiniz.

![Tuist ile generate komutunu çalıştırmak için bir şema yapılandırması
örneği](/images/contributors/scheme-arguments.png)

Ayrıca çalışma dizinini oluşturulmakta olan projenin kök dizinine ayarlamanız
gerekecektir. Bunu ya tüm komutların kabul ettiği `--path` argümanını kullanarak
ya da çalışma dizinini aşağıda gösterildiği gibi şemada yapılandırarak
yapabilirsiniz:


![Tuist'i çalıştırmak için çalışma dizininin nasıl ayarlanacağına dair bir
örnek](/images/contributors/scheme-working-directory.png)

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
`tuist` CLI, `ProjectDescription` çerçevesinin yerleşik ürünler dizininde
bulunmasına bağlıdır. ` tuist`, `ProjectDescription` çerçevesini bulamadığı için
çalışmazsa, önce `Tuist-Workspace` şemasını oluşturun.
<!-- -->
:::

### Terminalden {#from-the-terminal}

Tuist'in kendisini kullanarak `run` komutu aracılığıyla `tuist`
çalıştırabilirsiniz:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Alternatif olarak, doğrudan Swift paketi Yöneticisi aracılığıyla da
çalıştırabilirsiniz:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
