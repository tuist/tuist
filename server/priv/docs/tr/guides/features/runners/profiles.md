---
{
  "title": "Profiller",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Çalıştırıcı profilleri, Tuist Çalıştırıcıları için bir platform, boyut, Ubuntu sürümü veya Xcode sürümü seçmek üzere runs-on üzerinden başvurduğunuz adlandırılmış makine yapılandırmalarıdır."
}
---
# Profiller {#profiles}

**Profil**, hesap düzeyinde tanımlanmış, adlandırılmış bir makine şeklidir. Bir iş akışının `runs-on` alanından bu profile başvurursunuz ve Tuist, işi eşleşen bir çalıştırıcıya yönlendirir. Profiller, altyapı tercihlerinizi (platform, boyut, Ubuntu sürümü veya Xcode sürümü) her iş akışı dosyasına dağıtmak yerine tek bir yerde toplar ve CI sistemlerinizin işaretleyebileceği sabit bir etiket sağlar.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

Etiket, profilin adına `tuist-` ön eki eklenerek oluşturulur. Adı `macos` olan bir profil `runs-on: tuist-macos` şeklindedir; adı `linux-large` olan bir profil ise `runs-on: tuist-linux-large` şeklindedir. Eşleştirme büyük/küçük harfe duyarlı değildir.

## Varsayılan profiller {#default-profiles}

Runners özelliği etkinleştirilen her hesap, herhangi bir yapılandırma yapmadan filoyu kullanabilmeniz için iki varsayılan profille başlar:

{{runner_default_profiles_table}}

Her ikisi de platformları için varsayılan <.localized_link href="/guides/features/runners/profiles#machine-shapes">şekle</.localized_link> işaret eder. Bu profiller **korunmalıdır**, bu nedenle silinemezler ve iş akışlarınızın bağımlı olduğu etiketler her zaman çözümlenir. Şekillerini veya Xcode sürümlerini değiştirebilir, diğer boyutlar veya Xcode sürümleri için ek profiller oluşturabilirsiniz.

## Makine şekilleri {#machine-shapes}

Çalıştırıcılar macOS'ta (Apple silikon, Mac filosunda sanallaştırılmış) ve Linux'ta kullanılabilir. Her profil, aşağıdaki katalogdan bir makine şeklini, yani bir `(vCPUs, memory)` çiftini sabitler.

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux profilleri ayrıca bir **Ubuntu sürümü** seçer; tıpkı macOS profillerinin bir Xcode sürümü seçmesi gibi:

- **Ubuntu 24.04** (`ubuntu-24.04`), yeni profiller için varsayılan sürümdür.
- **Ubuntu 22.04** (`ubuntu-22.04`), hâlâ ihtiyaç duyan iş akışları içindir. GitHub, 22.04 barındırılan imajını kullanım dışı bıraktı ve 17 Nisan 2027 tarihinde kaldıracaktır; o tarihe kadar geçiş yapmayı planlayın.

Bir profil, siz değiştirene kadar seçtiğiniz sürümde kalır; bu nedenle daha yeni bir varsayılan sürüm, işlerinizi kendi başına başka bir işletim sistemine taşımaz. 24.04 üzerinde derlenen ikili dosyalar, daha yeni glibc (2.39) gerektirir ve eski sistemlerde çalışmayabilir. Ayrıca sistem Python'u, sanal ortam dışında `pip install` komutunu reddeder (PEP 668). Çalıştırıcı, GitHub tarafından barındırılan çalıştırıcılar gibi `ImageOS` değerini (`ubuntu24` veya `ubuntu22`) ayarlar, böylece kurulum eylemleri doğru sürüm için derlemeleri seçer.

Her Linux profili, `/dev/kvm` üzerinden <.localized_link href="/guides/features/runners#android-emulators">donanım hızlandırmalı Android öykünücülerini</.localized_link> destekler. Ayrı bir KVM profili gerekmez.

### macOS {#macos}

{{runner_macos_shapes_table}}

Daha büyük macOS şekilleri filodaki daha az makinede çalıştırıldığından, bu şekli isteyen bir iş, daha küçük bir şekil üzerindeki aynı işe göre başlaması için daha uzun süre bekleyebilir. Bir iş CPU ile sınırlıysa daha büyük bir şekil tercih edin; diğer durumlar için varsayılan şekli koruyun. Emin değilseniz, işi her iki şekilde de çalıştırın ve panodaki süreleri karşılaştırın.

macOS profilleri ayrıca bir **Xcode sürümünü** sabitler. Sürüm, ilgili Xcode'un önceden yüklendiği bir çalıştırıcı imajı seçer, böylece işler araç zinciri zaten hazır halde başlar. Her imajın içerdiği diğer bileşenler için <.localized_link href="/guides/features/runners/images">İmajlar</.localized_link> bölümüne bakın. Günümüzde desteklenen sürümler:

{{runner_macos_xcode_versions}}

> [!NOTE]
> Donanım ve Xcode sürümleri eklendikçe katalog gelişir. Panodaki **Yeni profil** formu ve `tuist runner profile catalog` her zaman hesabınız için şu anda kullanılabilir olan şekilleri, Xcode sürümlerini ve Ubuntu sürümlerini gösterir; bu nedenle bunları güvenilir kaynak olarak kabul edin.

Bir macOS çalıştırıcısının adı, çalıştırdığı macOS sürümünü, profilin Xcode sürümünü ve şeklini gösterir; örneğin `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`. Bu ad, GitHub'daki işin **İşi ayarla** adımında ve Tuist panosundaki iş ayrıntılarında görünür.

## Profil oluşturma {#creating-a-profile}

1. Hesap panonuzdaki **Çalıştırıcılar → Profiller** bölümünü açın.
2. **Yeni profil** seçeneğini belirleyin.
3. Bir ad verin, bir platform seçin ve bir şekil belirleyin. Linux için ayrıca bir Ubuntu sürümü; macOS için bir Xcode sürümü seçin.
4. Kaydedin, ardından bir iş akışından `runs-on: tuist-<name>` kullanarak bu profile başvurun.

Profilleri komut satırından da yönetebilirsiniz. Profil oluşturma, değiştirme ve silme işlemleri, panoda olduğu gibi hesap yöneticisi yetkisi veya `account:runners:write` kapsamına sahip bir hesap jetonu gerektirir:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Ajanlar aynı işlemi <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusu</.localized_link> aracılığıyla gerçekleştirebilir.

Örneğin, 8 vCPU / 32 GB şeklinde adı `linux-large` olan bir profil:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

Veya Xcode `26.4.1` sürümüne sabitlenmiş, adı `xcode-26-4` olan bir macOS profili; böylece varsayılan `macos` profiliniz en son sürümü takip ederken bir iş daha eski bir araç zincirinde çalışabilir:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
