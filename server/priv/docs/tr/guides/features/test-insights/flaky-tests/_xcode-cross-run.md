### Çapraz çalıştırma algılama {#cross-run-detection}

Test yeniden denemeleri olmasa bile Tuist, aynı commit, şema ve bildirilen hedef (cihaz adı, platform ve işletim sistemi sürümü) üzerindeki farklı CI çalıştırmalarındaki sonuçları karşılaştırarak kararsız testleri algılayabilir. Bir test eşleşen bir CI çalıştırmasında başarılı olurken başka birinde başarısız olursa, başarısız olan yürütme kararsız olarak işaretlenir. Bu, hangi sonucun önce geldiğinden bağımsız olarak çalışır.

Aynı test, şemalar veya hedefler arasında tutarlı biçimde farklı davranabilir. Örneğin, iOS 26’da başarılı olup iOS 27’de başarısız olması kararsızlığı göstermez. Farklı şemalardan, cihazlardan, platformlardan veya işletim sistemi sürümlerinden gelen sonuçlar birbirini kararsız olarak işaretlemez.

Hedef meta verisi olmayan veya birden çok hedefi kapsayan çalıştırmalar yalnızca kendi aralarında karşılaştırılır; bu nedenle aralarındaki ortam farkları yine de kararsız olarak raporlanabilir. Yeniden denemeye dayalı algılama geçerliliğini korur.

Bu yaklaşım, yeniden denemelerle yakalanacak kadar tutarlı başarısız olmasa da ara sıra CI hatalarına neden olan kararsız testleri tespit etmek için özellikle faydalıdır.
