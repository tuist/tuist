### Her testin kaç kez yeniden çalıştırıldığı {#stress-reruns}

İlk geçişte test senaryosunun ne kadar sürdüğüne bağlıdır:

| İlk geçiş | Yeniden çalıştırmalar |
| --- | --- |
| 5 saniyeye kadar | 10 |
| 10 saniyeye kadar | 5 |
| 30 saniyeye kadar | 3 |
| 5 dakikaya kadar | 2 |
| 5 dakikadan fazla | Yeniden çalıştırılmaz |

Geçiş, 200 test senaryosuna veya 10 dakikaya ulaştığında (hangisi önce gelirse) durur ve hangi limite takıldığını belirtir.
