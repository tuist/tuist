## Kararsız testleri yönetme {#managing-flaky-tests}

### Otomatik temizleme {#automatic-clearing}

Algılama ve temizleme, proje üzerindeki bir **otomasyon uyarısı** aracılığıyla çalışır. Her projede, bir testi kararsız olarak işaretleyen *tetikleme* ve test yeniden tetiklenmeden yapılandırılmış kurtarma penceresi (varsayılan **14 gün**) boyunca geçtiğinde işareti kaldıran *kurtarma* adımlarına sahip varsayılan bir "Kararsız test algılama" otomasyonu bulunur. Kurtarma penceresini değiştirmek, kurtarma eylemlerini değiştirmek (örneğin, testi karantinadan da çıkarmak) veya kurtarmayı tamamen devre dışı bırakmak için **Ayarlar → Otomasyonlar** altında düzenleyin; böylece testler, siz elle temizleyene kadar kararsız olarak işaretli kalır.

### Manuel yönetim {#manual-management}

Test senaryosu detay sayfasından testleri manuel olarak kararsız olarak işaretleyebilir veya işareti kaldırabilirsiniz. Bu durum şu durumlarda faydalıdır:
- Bir düzeltme üzerinde çalışırken bilinen bir kararsız testi onaylamak istediğinizde
- Bir test, altyapı sorunları nedeniyle yanlışlıkla işaretlendiğinde
