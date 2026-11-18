---
{
  "title": "Profiller",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "Çalıştırıcı profilleri, Tuist Çalıştırıcıları için bir platform, boyut, Ubuntu sürümü veya Xcode sürümü seçmek üzere runs-on üzerinden başvurduğunuz adlandırılmış makine yapılandırmalarıdır."
}
---
# Profiller {#profiles}

**Profil**, hesap düzeyinde tanımlanmış, adlandırılmış bir makine şeklidir. Bir iş akışının `runs-on` alanından bu profile başvurursunuz ve Tuist işi eşleşen bir çalıştırıcıya yönlendirir. Profiller, altyapı tercihlerinizi (platform, boyut, Ubuntu sürümü veya Xcode sürümü) her iş akışı dosyasına dağıtmak yerine tek bir yerde tutar ve CI sistemlerinin işaretleyebileceği kararlı bir etiket sağlar.

```yaml
jobs:
  build:
    runs-on: tuist-macos
```

Etiket, profilin adına `tuist-` ön eki eklenerek oluşturulur. `macos` adlı bir profil `runs-on: tuist-macos` şeklindedir; `linux-large` adlı bir profil ise `runs-on: tuist-linux-large` şeklindedir. Eşleştirme büyük/küçük harfe duyarlı değildir.

## Varsayılan profiller {#default-profiles}

Runners özelliği etkinleştirilen her hesap, herhangi bir yapılandırma yapmadan filoyu kullanabilmeniz için iki varsayılan profille başlar:

{{runner_default_profiles_table}}

Her ikisi de kendi platformları için varsayılan <.localized_link href="/guides/features/runners/profiles#machine-shapes">şekli</.localized_link> işaret eder. Bu profiller **korunmalıdır**, bu nedenle silinemezler ve iş akışlarınızın bağımlı olduğu etiketler her zaman çözümlenir. Yine de şekillerini veya Xcode sürümlerini değiştirebilir ve diğer boyutlar veya Xcode sürümleri için ek profiller oluşturabilirsiniz.

## Makine şekilleri {#machine-shapes}

Çalıştırıcılar macOS (Apple silicon, Mac filosunda sanallaştırılmış) ve Linux üzerinde kullanılabilir. Her profil, aşağıdaki katalogdan bir makine şeklini, yani bir `(vCPUs, memory)` çiftini sabitler.

### Linux {#linux}

{{runner_linux_shapes_table}}

Linux profilleri ayrıca bir **Ubuntu sürümü** seçer; tıpkı macOS profillerinin bir Xcode sürümü seçmesi gibi:

- **Ubuntu 24.04** (`ubuntu-24.04`), yeni profiller için varsayılan.
- **Ubuntu 22.04** (`ubuntu-22.04`), hâlâ ihtiyaç duyan iş akışları için. GitHub, 22.04 barındırılan imajını kullanım dışı bıraktı ve 17 Nisan 2027 tarihinde kaldırıyor; o tarihe kadar geçiş yapmayı planlayın.

Bir profil, siz değiştirene kadar seçtiğiniz sürümde kalır, bu nedenle daha yeni bir varsayılan sürüm işlerinizi kendiliğinden başka bir işletim sistemine taşımaz. 24.04 üzerinde derlenen ikililer daha yeni glibc (2.39) gerektirir ve eski sistemlerde çalışmayabilir; ayrıca sistem Python’u sanal ortam dışında `pip install` komutunu reddeder (PEP 668). Çalıştırıcı, GitHub tarafından barındırılan çalıştırıcılarda olduğu gibi `ImageOS` değerini (`ubuntu24` veya `ubuntu22`) ayarlar, böylece kurulum eylemleri doğru sürüm için derlemeleri seçer.

Her Linux profili, `/dev/kvm` üzerinden <.localized_link href="/guides/features/runners#android-emulators">donanım hızlandırmalı Android öykünücülerini</.localized_link> destekler. Ayrı bir KVM profili gerekmez.

### macOS {#macos}

{{runner_macos_shapes_table}}

Daha büyük macOS şekilleri filoda daha az makinede çalıştığından, bu şekli isteyen bir işin başlaması daha küçük bir şekle kıyasla daha uzun sürebilir. Bir iş CPU ile sınırlıysa daha büyük bir şekil tercih edin, diğer durumlar için varsayılan şekli koruyun. Emin değilseniz, işi her iki şekilde de çalıştırın ve panodaki süreleri karşılaştırın.

macOS profilleri ayrıca bir **Xcode sürümü** sabitler. Sürüm, ilgili Xcode’un önceden yüklü olduğu bir çalıştırıcı imajı seçer, böylece işler araç zinciri hazır halde başlar. Her imajın içerdiği diğer öğeler için <.localized_link href="/guides/features/runners/images">İmajlar</.localized_link> bölümüne bakın. Günümüzde desteklenen sürümler:

{{runner_macos_xcode_versions}}

> [!NOTE]
> Donanım ve Xcode sürümleri eklendikçe katalog gelişir. Panodaki **Yeni profil** formu ve `tuist runner profile catalog` her zaman hesabınız için şu anda kullanılabilir olan şekilleri, Xcode sürümlerini ve Ubuntu sürümlerini gösterir; bu nedenle onları güvenilir kaynak olarak kabul edin.

Bir macOS çalıştırıcısının adı, çalıştırdığı macOS sürümünü, profilin Xcode sürümünü ve şeklini gösterir; örneğin `tuist-macos-26.6-xcode-27.0-8vcpu-24gb-1a2b3c4d5e6f`. Bu ad, GitHub’daki işin **İşi kur** adımında ve Tuist panosundaki iş ayrıntılarında görünür.

## Profil oluşturma {#creating-a-profile}

1. Hesap panonuzdaki **Çalıştırıcılar → Profiller** bölümünü açın.
2. **Yeni profil** seçeneğini belirleyin.
3. Bir ad verin, bir platform seçin ve bir şekil belirleyin. Linux için ayrıca bir Ubuntu sürümü; macOS için bir Xcode sürümü seçin.
4. Kaydedin, ardından bir iş akışından `runs-on: tuist-<name>` ile buna başvurun.

Profilleri komut satırından da yönetebilirsiniz. Profil oluşturma, değiştirme ve silme işlemi, panodaki gibi hesap yöneticisi yetkisi veya `account:runners:write` kapsamına sahip bir hesap jetonu gerektirir:

```bash
tuist runner profile catalog
tuist runner profile create linux-large --platform linux --vcpus 8 --memory-gb 32
tuist runner profile update linux-large --vcpus 16 --memory-gb 32
tuist runner profile delete linux-large --yes
```

Ajanlar aynı işlemi <.localized_link href="/guides/features/agentic-coding/mcp">MCP sunucusu</.localized_link> aracılığıyla gerçekleştirebilir.

Örneğin, 8 vCPU / 32 GB şeklinde `linux-large` adlı bir profil:

```yaml
jobs:
  integration-tests:
    runs-on: tuist-linux-large
```

Veya Xcode `26.4.1` sürümüne sabitlenmiş `xcode-26-4` adlı bir macOS profili; böylece varsayılan `macos` profiliniz en son sürümü takip ederken bir iş daha eski bir araç zincirinde çalışabilir:

```yaml
jobs:
  build-legacy:
    runs-on: tuist-xcode-26-4
```
