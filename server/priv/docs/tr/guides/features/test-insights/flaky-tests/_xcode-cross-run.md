### Çalışmalar arası tespit {#cross-run-detection}

Test yeniden denemeleri olmasa bile, Tuist aynı commit, şema ve bildirilen hedef (cihaz adı, platform ve işletim sistemi sürümü) üzerindeki farklı CI çalıştırmalarındaki sonuçları karşılaştırarak kararsız testleri tespit edebilir. Bir test eşleşen bir CI çalıştırmasında geçip diğerinde başarısız olursa, başarısız olan yürütme kararsız olarak işaretlenir. Bu, hangi sonucun önce geldiğinden bağımsız olarak çalışır.

Aynı test, şemalar veya hedefler arasında tutarlı şekilde farklı davranabilir. Örneğin, iOS 26’da başarılı olup iOS 27’de başarısız olması kararsızlığı göstermez. Farklı şemalardan, cihazlardan, platformlardan veya işletim sistemi sürümlerinden gelen sonuçlar birbirini kararsız olarak işaretlemez.

Hedef meta verisi olmayan veya birden fazla hedefi kapsayan çalıştırmalar yalnızca kendi aralarında karşılaştırılır; bu nedenle aralarındaki ortam farkları yine de kararsız olarak bildirilebilir. Yeniden deneme tabanlı tespit hâlâ geçerlidir.

Bu yaklaşım, yeniden denemelerle yakalanacak kadar tutarlı başarısızlık göstermeyen ancak yine de ara sıra CI hatalarına neden olan kararsız testleri yakalamak için özellikle kullanışlıdır.
