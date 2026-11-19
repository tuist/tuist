### Çalışmalar arası tespit {#cross-run-detection}

Test yeniden denemeleri olmasa bile, Tuist aynı commit, şema ve bildirilen hedef (cihaz adı, platform ve işletim sistemi sürümü) üzerindeki farklı CI çalışmaları arasındaki sonuçları karşılaştırarak kararsız testleri tespit edebilir. Bir test eşleşen bir CI çalışmasında geçip başka birinde başarısız olursa, başarısız olan yürütme kararsız olarak işaretlenir. Bu, hangi sonucun önce geldiğinden bağımsız olarak çalışır.

Aynı test, şemalar veya hedefler arasında tutarlı şekilde farklı davranabilir. Örneğin, iOS 26’da geçip iOS 27’de başarısız olması kararsızlığı göstermez. Farklı şemalardan, cihazlardan, platformlardan veya işletim sistemi sürümlerinden gelen sonuçlar birbirini kararsız olarak işaretlemez.

Hedef meta verisi olmayan veya birden fazla hedefi kapsayan çalışmalar yalnızca birbirleriyle karşılaştırılır; bu nedenle aralarındaki ortam farklılıkları yine de kararsız olarak raporlanabilir. Yeniden denemeye dayalı tespit hâlâ geçerlidir.

Bu, yeniden denemelerle yakalanacak kadar tutarlı başarısız olmasa da yine de ara sıra CI hatalarına neden olan kararsız testleri yakalamak için özellikle kullanışlıdır.
