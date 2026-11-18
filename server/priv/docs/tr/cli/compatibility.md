---
{
  "title": "Uyumluluk",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist sunucusunun eski CLI sürümlerini ne kadar süreyle desteklediği, destek penceresinin yükseltmeler için ne anlama geldiği ve bu pencerenin dışındaki sürümlere ne olduğu."
}
---

# Uyumluluk {#compatibility}

Tuist CLI; önbellek, derleme ve test analizleri, önizlemeler ve kayıt defteri gibi özellikler için Tuist sunucusuyla iletişim kurar. Sunucu, CLI sürümünü yükselttiğiniz zamandan bağımsız olarak sürekli olarak güncellenir; bu nedenle bir sunucu değişikliği, çalıştırdığınız CLI sürümünü bozmamalıdır. Bunu garanti etmek için sunucu, belirli bir süre boyunca yeni CLI sürümleriyle uyumlu kalır.

## Destek penceresi {#support-window}

Tuist sunucusu, **son 3 ay** içinde yayınlanan CLI sürümlerini destekler. Bu pencere içinde sunucu geriye dönük uyumluluğu korur: Son 3 ayda yayınlanan herhangi bir CLI, sunucuya karşı derleme, önbellekleme ve test çalıştırma işlemlerini sürdürür; böylece bir sunucu değişikliği sizi etkilemeden CLI'yı kendi planınıza göre yükseltebilirsiniz.

CLI, [anlamsal sürümleme](https://semver.org) ilkelerini izler. Son 3 ay içinde yayımlanan her sürüm desteklenir.

## Pencere dışında {#outside-the-window}

Destek penceresinden daha eski olan CLI sürümleri kullanımdan kaldırılmış kabul edilir. Sunucu hâlâ yanıt verir, ancak:

- Daha yeni sunucu tarafı özellikler bu sürümle çalışmayabilir.
- Sunucu destekli komutlar, sizi yükseltmeye davet eden bir uyarı yazdırabilir.

Kullanımdan kaldırılmış sürümlerdeki davranış garanti edilmez. Böyle bir sürüm kullanıyorsanız, destek penceresi içindeki bir sürüme yükseltin.

## Vaadi nasıl yerine getiriyoruz {#how-we-keep-the-promise}

Geriye dönük uyumluluk varsayılmaz, doğrulanır. Her sunucu dağıtımı, **destek penceresi içinde kalan en eski CLI sürümüne** karşı otomatik bir kabul testi çalıştırır; bu sürüm şu anda `{{minimum_supported_cli_version}}` olup önbellek çekme yolunu uçtan uca test eder. Bir değişiklik bu sürümü bozacaksa, dağıtım üretime ulaşmadan önce engellenir. Bu işlem, en son CLI'ya karşı yapılan testlerle birlikte yürütülür; böylece eski istemcilerdeki bir regresyon, en yeni istemcideki bir regresyonla aynı şekilde yakalanır.

## Öneri {#recommendation}

Desteklenen pencerede kalmak için CLI'yı en az 3 ayda bir kez yükseltin. CI ortamında CLI sürümünü sabitlemek ve düzenli aralıklarla güncellemek, ekibinizin tutarlı ve desteklenen bir sürümde kalmasını sağlar.
