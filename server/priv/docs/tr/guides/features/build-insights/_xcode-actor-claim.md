## Rapor aktör talebi {#report-actor-claim}

Rapor oluşturma istekleri, yalnızca `TUIST_ACTOR_ID` değerini kuruluş kapsamlı bir etikete açıkça ayarladığınızda isteğe bağlı `x-tuist-actor-id` başlığını içerir; örneğin `TUIST_ACTOR_ID=employee-123 tuist inspect build`. Varsayılan olarak hiçbir etiket gönderilmez ve Tuist işletim sistemi kullanıcı adlarını algılamaz. Boş bir `TUIST_ACTOR_ID`, bildirilen tanımlayıcıyı dışlar ancak kimlik bilgisi tabanlı doğrulanmış kimliği kaldırmaz. Tanımlayıcılar, boşluk içermeyen yazdırılabilir ASCII karakterlerden oluşan 1–128 bayt olmalıdır; geçersiz geçersiz kılmalar geri dönüş olmadan atlanır. Özel bir proxy bilinmeyen başlıkları reddederse, boş ortam geçersiz kılmasıyla devre dışı bırakın.

Doğrulanmış bireysel kimlik bilgileri önceliklidir; aksi takdirde istemci tarafından bildirilen tanımlayıcılar **Doğrulanmamış** olarak gösterilir ve asla izin vermez veya kullanıcılara otomatik olarak bağlanmaz. Tanımlayıcılar, projenin raporlarını görüntüleyebilen herkes tarafından görülebilir (proje herkese açık olduğunda genel izleyiciler dahil) ve veri dışa aktarmalarına dahil edilir, bu nedenle gizli bilgiler eklemeyin. Bu durum derleme, test ve komut olayı raporları için geçerlidir. Eski sunucular isteğe bağlı başlığı yoksayar ve yeni sunucular eski istemcileri bu başlık olmadan kabul eder. Tanımlayıcı içermeyen yeni paylaşılan token raporları, yayıncı kuruluş yerine **Bilinmiyor** gösterir; geçmiş raporlar önceki atıflarını korur. Derleme ve test listeleri, doğrulanmış kullanıcıları doğrulanmamış bildirilen tanımlayıcılardan ayırır. Kendi kendine barındırılan örnek kimlik bilgisi gerektirmeyen raporlamayı açıkça etkinleştirmediği ve istemci bu ilkeyi keşfetmediği sürece kimlik doğrulama gerekli olmaya devam eder.

### Şema sonrası eylemler {#actor-claim-post-actions}

Aktör talepleri varsayılan olarak devre dışıdır. Bir şema sonrası eylem için yapılandırmak üzere, kabuk dışa aktarmalarına güvenmek yerine o betikte `TUIST_ACTOR_ID` değerini ayarlayın. Dock'tan başlatılan Xcode, `~/.zshrc` içindeki değişkenleri miras almaz. Homebrew ile yapılandırılmış bir talebi açıkça bastırmak için şunu kullanın:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Mise ile, Mise ortamını yükledikten sonra değeri geçersiz kılın:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

Katılmak için boş değer yerine açık bir etiket kullanın.
