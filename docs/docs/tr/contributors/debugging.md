---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# Hata Ayıklama {#debugging}

Açık olmak pratik bir avantajdır: kod mevcuttur, yerel olarak
çalıştırabilirsiniz ve kodlama ajanlarını kullanarak soruları daha hızlı
yanıtlayabilir ve kod tabanındaki olası hataları giderebilirsiniz.

Hata ayıklama sırasında eksik veya tamamlanmamış belgeler bulursanız, `docs/`
adresindeki İngilizce belgeleri güncelleyin ve bir PR açın.

## Kodlama ajanları kullanın {#use-coding-agents}

Kodlama ajanları şunlar için kullanışlıdır:

- Kod tabanını tarayarak davranışın uygulandığı yeri bulun.
- Sorunları yerel olarak yeniden üretin ve hızlı bir şekilde yineleyin.
- Tuist'te girdilerin nasıl aktığını izleyerek sorunun temel nedenini bulun.

Mümkün olduğunca küçük bir yeniden üretim paylaşın ve temsilciye belirli
bileşeni (CLI, sunucu, önbellek, belgeler veya el kitabı) gösterin. Kapsam ne
kadar odaklanmışsa, hata ayıklama süreci o kadar hızlı ve doğru olur.

### Sık Kullanılan İpuçları (FNP) {#frequently-needed-prompts}

#### Beklenmeyen proje oluşturma {#unexpected-project-generation}

Proje oluşturma işlemi beklediğimden farklı bir sonuç veriyor. Bunun nedenini
anlamak için Tuist CLI'yi `/path/to/project` adresindeki projemde çalıştırın.
Oluşturucu boru hattını izleyin ve çıktıyı oluşturan kod yollarını belirleyin.

#### Oluşturulmuş projelerde tekrarlanabilir hata {#reproducible-bug-in-generated-projects}

Bu, oluşturulmuş projelerde bir hata gibi görünüyor. `examples/` altında, mevcut
örnekleri referans olarak kullanarak tekrarlanabilir bir proje oluşturun.
Başarısız olan bir kabul testi ekleyin, `xcodebuild` komutunu çalıştırın ve
yalnızca bu testi seçin, sorunu düzeltin, testi yeniden çalıştırarak başarılı
olduğunu doğrulayın ve bir PR açın.
