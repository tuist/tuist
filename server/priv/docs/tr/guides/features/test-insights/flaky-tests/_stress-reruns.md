### Her testin kaç kez yeniden çalıştırıldığı {#stress-reruns}

Test senaryosunun ilk geçişte ne kadar sürdüğüne bağlıdır:

| İlk geçiş | Yeniden çalıştırmalar |
| --- | --- |
| 5 saniyeye kadar | 10 |
| 10 saniyeye kadar | 5 |
| 30 saniyeye kadar | 3 |
| 5 dakikaya kadar | 2 |
| 5 dakikadan fazla | Yeniden çalıştırılmaz |

Geçiş, 200 test senaryosu veya 10 dakika sınırına ulaştığında durur ve hangi sınıra takıldığını belirtir.
