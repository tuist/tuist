### Karantinaya alınan testler neden başarılı görünebilir {#quarantined-passing}

- **Sessize alınmış testler** hâlâ çalıştırılır. Başarısız olan sessize alınmış bir test, test senaryosu çalıştırmasında **başarısız** olarak kaydedilir ve kararsız olarak işaretlenir; test başına durum yeniden yazılmaz. Geçersiz kılınan şey **genel test çalıştırmasıdır**: Çalıştırmadaki başarısız her test senaryosu sessize alındıysa, çalıştırmanın tamamı başarılı olarak raporlanır; bu sayede sessize alınmış hatalar CI'yı bozmaz.
- **Atlanan testler** hiç çalışmaz, bu nedenle pano testin son gerçek çalıştırmasındaki durumu göstermeye devam eder. Bu anlık görüntü haftalarca eski olabilir.
