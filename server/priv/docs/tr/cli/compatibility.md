---
{
  "title": "Uyumluluk",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist sunucusunun eski CLI sürümlerini ne kadar süreyle desteklediği, destek penceresinin yükseltmeler için ne anlama geldiği ve bu pencerenin dışındaki sürümlere ne olduğu."
}
---

# Uyumluluk {#compatibility}

Tuist CLI; önbellek, derleme ve test analizleri, önizlemeler ve kayıt defteri gibi özellikler için Tuist sunucusuyla iletişim kurar. Sunucu, CLI sürümünü ne zaman yükselttiğinizden bağımsız olarak sürekli şekilde güncellenir; bu nedenle bir sunucu değişikliği çalıştırdığınız CLI sürümünü bozmamalıdır. Bunu garanti etmek için sunucu, belirlenen bir süre boyunca son CLI sürümleriyle uyumlu kalır.

## Destek penceresi {#support-window}

Tuist sunucusu, **son 3 ay** içinde yayımlanan CLI sürümlerini destekler. Bu pencere içinde sunucu geriye dönük uyumluluğu korur: Son 3 ayda yayımlanan herhangi bir CLI, sunucuya karşı derleme, önbellekleme ve test çalıştırma işlemlerini sürdürür; siz de bir sunucu değişikliği sizi etkilemeden CLI’yı kendi planınıza göre yükseltebilirsiniz.

CLI, [anlamsal sürümleme](https://semver.org) ilkelerini izler. Son 3 ay içinde yayımlanan her sürüm desteklenir.

## Pencere dışında {#outside-the-window}

Destek penceresinden daha eski olan CLI sürümleri kullanımdan kaldırılmış kabul edilir. Sunucu yine yanıt verir, ancak:

- Daha yeni sunucu tarafı özellikler o sürümle çalışmayabilir.
- Sunucu destekli komutlar, yükseltme yapmanızı isteyen bir uyarı yazdırabilir.

Kullanımdan kaldırılmış sürümlerdeki davranış garanti edilmez. Böyle bir sürüm kullanıyorsanız, destek penceresi içindeki bir sürüme yükseltin.

## Vaadi nasıl yerine getiriyoruz {#how-we-keep-the-promise}

Geriye dönük uyumluluk varsayılmaz, doğrulanır. Her sunucu dağıtımı, **destek penceresi içinde kalan en eski CLI sürümüne** karşı otomatik bir kabul testi çalıştırır; bu sürüm şu anda `{{minimum_supported_cli_version}}` olup önbellek çekme yolunu uçtan uca çalıştırır. Bir değişiklik bu sürümü bozacaksa, dağıtım üretim ortamına ulaşmadan önce engellenir. Bu işlem, en son CLI’ya karşı yapılan testlerle birlikte yürütülür; böylece eski istemcilerdeki gerilemeler, en yeni istemcideki gerilemelerle aynı şekilde yakalanır.

## Öneri {#recommendation}

Desteklenen pencere içinde kalmak için CLI’yı en az 3 ayda bir kez yükseltin. CLI sürümünü CI’da sabitleyip düzenli aralıklarla güncellemek, ekibinizin tutarlı ve desteklenen bir sürümde kalmasını sağlar.
