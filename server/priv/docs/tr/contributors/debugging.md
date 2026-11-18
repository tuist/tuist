---
{
  "title": "Hata Ayıklama",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Tuist'teki sorunları hata ayıklamak için kodlama ajanlarını ve yerel çalıştırmaları kullanın."
}
---
# Hata Ayıklama {#debugging}

Açık kaynak olmak pratik bir avantajdır: kod mevcuttur, yerel olarak çalıştırabilirsiniz ve soruları daha hızlı yanıtlamak ile kod tabanındaki olası hataları ayıklamak için kodlama ajanlarını kullanabilirsiniz.

Hata ayıklama sırasında eksik veya tamamlanmamış belgelerle karşılaşırsanız, `server/priv/docs/en` altındaki İngilizce belgeleri güncelleyin ve bir PR açın.

## CI üzerinde yığın dökümlerini yakalama {#thread-dump-ci}

CLI ara sıra takılıp kaldığında, işlemi durdurmadan bir yığın dökümü yakalayabilirsiniz. Sinyal işleyicisini etkinleştirin ve çalışan `tuist` işlemine `SIGUSR1` gönderin.

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

`TUIST_THREAD_DUMP_SAMPLE` ayarlanmamışsa, işleyici geçerli iş parçacığı yığınına yazdırır. Çıktı stderr'e yazıldığından CI günlüklerinde görünür.

## Kodlama ajanlarını kullanma {#use-coding-agents}

Kodlama ajanları şu durumlar için faydalıdır:

- Bir davranışın nerede uygulandığını bulmak için kod tabanını tarama.
- Sorunları yerel olarak yeniden üretme ve hızlıca yineleme yapma.
- Kök nedeni bulmak için girdilerin Tuist üzerinden nasıl aktığını izleme.

Mümkün olan en küçük yeniden üretim örneğini paylaşın ve ajanı belirli bileşene (CLI, sunucu, önbellek, belgeler veya el kitabı) yönlendirin. Kapsam ne kadar odaklı olursa, hata ayıklama süreci o kadar hızlı ve doğru olur.

### Sıkça Gereken İstemler (FNP) {#frequently-needed-prompts}

#### Beklenmeyen proje oluşturma {#unexpected-project-generation}

Proje oluşturma beklediğimden farklı bir sonuç veriyor. Bunun neden olduğunu anlamak için Tuist CLI'yi `/path/to/project` konumundaki projeme karşı çalıştırın. Oluşturucu hattını izleyin ve çıktıdan sorumlu kod yollarını işaret edin.

#### Oluşturulan projelerde tekrarlanabilir hata {#reproducible-bug-in-generated-projects}

Bu, oluşturulan projelerde bir hata gibi görünüyor. Mevcut örnekleri referans alarak `examples/` altında tekrarlanabilir bir proje oluşturun. Başarısız olan bir kabul testi ekleyin, yalnızca bu testi seçerek `xcodebuild` ile çalıştırın, sorunu düzeltin, geçtiğini doğrulamak için testi yeniden çalıştırın ve bir PR açın.
