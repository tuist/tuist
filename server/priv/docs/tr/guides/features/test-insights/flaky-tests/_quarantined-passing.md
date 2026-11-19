### Karantinaya alınan testlerin neden başarılı olarak görünebileceği {#quarantined-passing}

- **Sessize alınmış testler** yine de çalıştırılır. Başarısız olan sessize alınmış bir test, test senaryosu çalıştırmasında **başarısız** olarak kaydedilir ve kararsız olarak işaretlenir; test başına durum yeniden yazılmaz. Geçersiz kılınan şey **genel test çalıştırmasıdır**: Çalıştırmadaki başarısız olan her test senaryosu sessize alındıysa, çalıştırmanın tamamı başarılı olarak raporlanır; bu sayede sessize alınmış hatalar CI'yi bozmaz.
- **Atlanan testler** hiç çalıştırılmaz, bu nedenle pano testin son gerçek çalıştırmasındaki durumu göstermeye devam eder. Bu anlık görüntü haftalarca eski olabilir.
