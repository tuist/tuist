---
{
  "title": "Desteklenen önizleme türleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Mobil uygulamalar, macOS uygulamaları ve komut satırı önizlemeleri için paketleme ve uyumluluk gereksinimleri."
}
---
# Desteklenen önizleme türleri

Önizleme türü, onu üreten derleme sisteminden bağımsız olarak neyi paketlediğinizi ve nerede çalıştırabileceğinizi belirler. Her yayınlama iş akışının kendi imzalama ve uygunluk gereksinimleri vardır.

## Mobil uygulamalar {#mobile-apps}

- **Android:** imzalı bir uygulama APK’sı. Alıcıların uyumlu bir Android cihazına veya öykünücüsüne ihtiyacı vardır. Android Uygulama Paketleri (`.aab`) önizleme kurulum paketleri değildir.
- **Apple:** simülatör için bir uygulama paketi veya fiziksel cihazlar için dışa aktarılmış bir IPA. Cihaz derlemeleri, alıcının cihazına kuruluma izin veren bir sağlama profiline ihtiyaç duyar.

<.localized_link href="/guides/features/previews/xcode">Xcode</.localized_link>, <.localized_link href="/guides/features/previews/gradle">Gradle</.localized_link> ve <.localized_link href="/guides/features/previews/bazel">Bazel</.localized_link> kılavuzları, her iş akışının hangi çıktıları yayınlayabileceğini açıklar. Örneğin, Bazel ve Struo yayınlaması uygun Apple simülatör ve macOS uygulamalarını destekler, fiziksel cihaz derlemelerini değil.

## Masaüstü uygulamaları {#desktop-apps}

Derlenmiş bir macOS uygulama paketini paylaşın:

```bash
tuist share path/to/MyApp.app
```

İmzalama ve onaylama gereksinimleri hâlâ geçerlidir. Masaüstü uygulama paketi, alıcıların önizlemeleri çalıştırmak için kullanabileceği Tuist macOS uygulamasından farklıdır.

## Komut satırı araçları {#command-line-tools}

macOS veya Linux’ta bağımsız bir çalıştırılabilir dosyayı paylaşın:

```bash
tuist share path/to/my-tool
```

CLI’ın kaynak paketlerine, dinamik kütüphanelere veya yardımcı çalıştırılabilir dosyalara ihtiyacı varsa, bir dağıtım dizini oluşturun ve giriş noktasını bu dizine göre belirtin:

```bash
tuist share path/to/distribution --executable bin/my-tool
```

Tüm dağıtım dizini yüklenir. Aracınızın ihtiyaç duyduğu kütüphaneleri, kaynakları ve yardımcıları ekleyin ve derleme dizininizin dışında çalışabildiğinden emin olun. Betiklerin shebang satırına ve alıcının sisteminde kurulu bir yorumlayıcıya ihtiyacı vardır.

Çalıştırılabilir dosyaların kendi simgesi yoktur. Önizlemede bir simge göstermek için `--icon` ile bir PNG iletin; örneğin bir Linux masaüstü uygulaması için:

```bash
tuist share path/to/distribution --executable bin/my-app --icon path/to/icon.png
```

## Birden çok CLI hedefi {#multiple-cli-targets}

Bir önizleme, tek bir commit için aynı CLI’ın derlemelerini gruplar; her derleme tek bir işletim sistemi ve bir veya daha fazla CPU mimarisi için bir dağıtım içerir. Örneğin, tek bir önizleme macOS arm64, macOS x86_64 ve Linux x86_64 dağıtımlarını içerebilir. Evrensel bir macOS çalıştırılabilir dosyası, tek bir derlemede her iki Mac mimarisini de kapsar.

Her hedefi ayrı ayrı derleyin, ardından dağıtımları aynı Git kopyasından aynı giriş noktası temel adı ve izini kullanarak sırayla yayınlayın:

```bash
tuist share dist/macos-arm64 --executable bin/tuist --track pr
tuist share dist/macos-x86_64 --executable bin/tuist --track pr
tuist share dist/linux-x86_64 --executable bin/tuist --track pr
```

Bu yüklemeler, derlemeleri aynı önizleme bağlantısına ekler. Yüklemeler arasında proje, commit, yayınlama hesabı, CLI adı ve iz aynı kalmalıdır. Tuist, alıcının işletim sistemi ve CPU mimarisiyle eşleşen derlemeyi seçer.

## İstemci ve sunucu uyumluluğu {#client-and-server-compatibility}

Masaüstü ve komut satırı önizlemelerini çalıştırmak için güncel bir Tuist CLI kullanın. Tuist’i kendi barındırıyorsanız, bu türleri yayınlamadan önce sunucunuzu güncelleyin. Mobil önizlemeler eski istemcilerle çalışmaya devam eder.

Alıcılarınızın işletim sistemleri ve CPU mimarileri için derleme yapın. Tuist uygulamanızı çapraz derlemez veya bağımlılıklarını yüklemez; Linux araçları ayrıca uyumlu sistem kütüphanelerine ihtiyaç duyar.

Önizlemeler bir sanal alan içinde değil, kullanıcı hesabınızın izinleriyle çalışır. Yalnızca güvendiğiniz yazarlardan ve çekme isteklerinden gelen derlemeleri çalıştırın.

Çalıştırma davranışı ve argüman iletimi için <.localized_link href="/guides/features/previews/run/cli">CLI ile önizlemeleri çalıştırma</.localized_link> bölümüne; erişim, izler ve README rozetleri için <.localized_link href="/guides/features/previews#visibility">önizleme genel bakış</.localized_link> bölümüne bakın.
