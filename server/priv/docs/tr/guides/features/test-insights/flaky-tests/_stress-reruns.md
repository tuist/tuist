### Her test senaryosunun kaç kez yeniden çalıştırıldığı {#stress-reruns}

Bu, test senaryosunun ilk geçişte ne kadar sürdüğüne bağlıdır:

| İlk geçiş | Yeniden çalıştırma sayısı |
| --- | --- |
| 5 saniyeye kadar | 10 |
| 10 saniyeye kadar | 5 |
| 30 saniyeye kadar | 3 |
| 5 dakikaya kadar | 2 |
| 5 dakikadan fazla | Yeniden çalıştırılmaz |

Geçiş, hangisi önce gelirse 200 test senaryosunda veya 10 dakikada durur ve hangi sınıra ulaştığını belirtir.
