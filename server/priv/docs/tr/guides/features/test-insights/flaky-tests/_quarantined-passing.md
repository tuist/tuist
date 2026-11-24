### Karantinaya alınan testler neden başarılı görünebilir {#quarantined-passing}

- **Sessize alınmış testler** hâlâ çalıştırılır. Başarısız olan sessize alınmış bir test, test senaryosu çalıştırmasında **başarısız** olarak kaydedilir ve kararsız olarak işaretlenir; test başına durum yeniden yazılmaz. Geçersiz kılınan şey **genel test çalıştırması**dır: Çalıştırmadaki başarısız olan her test senaryosu sessize alındıysa, çalıştırmanın tamamı başarılı olarak raporlanır; böylece sessize alınmış hatalar CI'ı bozmaz.
- **Atlanan testler** hiç çalıştırılmaz, bu nedenle pano testin son gerçek çalıştırmasındaki durumu göstermeye devam eder. Bu anlık görüntü haftalarca eski olabilir.
