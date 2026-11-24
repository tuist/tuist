---
{
  "title": "Hata Ayıklama",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Tuist'teki sorunları hata ayıklamak için kodlama ajanlarını ve yerel çalıştırmaları kullanın."
}
---
# Hata Ayıklama {#debugging}

Açık kaynak olmak pratik bir avantajdır: kod mevcuttur, yerel olarak çalıştırabilirsiniz ve soruları daha hızlı yanıtlamak ile kod tabanındaki olası hataları ayıklamak için kodlama ajanlarını kullanabilirsiniz.

Hata ayıklama sırasında eksik veya tamamlanmamış belgeler bulursanız, `server/priv/docs/en` altındaki İngilizce belgeleri güncelleyin ve bir PR açın.

## CI'da thread dump yakalama {#thread-dump-ci}

CLI ara sıra takıldığında, işlemi durdurmadan bir thread dump yakalayabilirsiniz. Sinyal işleyicisini etkinleştirin ve çalışan `tuist` işlemine `SIGUSR1` gönderin.

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

`TUIST_THREAD_DUMP_SAMPLE` ayarlanmamışsa, işleyici mevcut thread yığınını yazdırır. Çıktı stderr'e yazılır, bu nedenle CI günlüklerinde görünür.

## Kodlama ajanlarını kullanma {#use-coding-agents}

Kodlama ajanları şu durumlar için faydalıdır:

- Bir davranışın nerede uygulandığını bulmak için kod tabanını tarama.
- Sorunları yerel olarak yeniden üretme ve hızla yineleme.
- Kök nedeni bulmak için girdilerin Tuist üzerinden nasıl aktığını izleme.

Mümkün olan en küçük yeniden üretimi paylaşın ve ajanı belirli bileşene (CLI, sunucu, önbellek, belgeler veya el kitabı) yönlendirin. Kapsam ne kadar odaklı olursa, hata ayıklama süreci o kadar hızlı ve doğru olur.

### Sıkça Gereken İstemler (FNP) {#frequently-needed-prompts}

#### Beklenmeyen proje üretimi {#unexpected-project-generation}

Proje üretimi beklediğim bir sonuç vermiyor. Bunun neden olduğunu anlamak için Tuist CLI'yi `/path/to/project` konumundaki projeme karşı çalıştırın. Üretici ardışık düzenini izleyin ve çıktıdan sorumlu kod yollarını işaret edin.

#### Üretilen projelerde tekrarlanabilir hata {#reproducible-bug-in-generated-projects}

Bu, üretilen projelerde bir hata gibi görünüyor. Mevcut örnekleri referans alarak `examples/` altında tekrarlanabilir bir proje oluşturun. Başarısız olan bir kabul testi ekleyin, yalnızca o testi seçerek `xcodebuild` ile çalıştırın, sorunu düzeltin, geçtiğini doğrulamak için testi yeniden çalıştırın ve bir PR açın.
