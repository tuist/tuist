---
locale: tr
glossary:
  tests: testler
  features: özellikler
  cache hit: önbellek isabeti
  cache miss: önbellek ıskalaması
  flaky tests: kararsız testler
  test run: test çalıştırması
  test case: test senaryosu
  selective testing: seçici test
---

## Turkish-specific translation rules

## Voice and Typography

- Write concise, natural Turkish for developers. Use a consistent button register, such as "Kaydet", "Uygula", and "İptal et", with polite plural instructions where appropriate in marketing. Omit unnecessary pronouns and avoid English sentence order.
- Use sentence case and locale-aware casing: `İ/i` and `I/ı` are distinct pairs. Omit final periods in headings, navigation, buttons, and short labels; retain normal punctuation in body copy.
- Attach suffixes using pronunciation and vowel harmony without changing protected identifiers. Ordinary inflected nouns do not take proper-name apostrophes: use "projelere", not "projele'ye".

## Developer Vocabulary and Marketing

- Keep cache hits and misses distinct, including in negative empty states. "No cache misses yet" must not become "Henüz önbellek isabeti yok" (no hits). "Remote hit" describes reuse from the remote cache, not "Uzak Erişim" (remote access).
- Removing a flaky flag is an action such as "Kararsız işaretini kaldır"; its confirmation can be "Kararsız işareti kaldırıldı". Do not translate these as "do not mark" or "was not marked". A newsletter issue is a "sayı", not a "sorun".
- Billing minutes measure usage, not the duration of a calendar period. "Geçen dönemde toplam %{count} dakika kullanıldı" and "Bu dönemde yaklaşık %{count} dakikalık kullanım bekleniyor" preserve past usage and estimated future usage respectively.
- "Shipping" means publishing software updates, not parcel delivery. For "More in the toolbox", prefer a clear heading such as "Ekibiniz için daha fazla araç". Read adjacent heading fragments together, for example "Gerçekten güvenebileceğiniz daha hızlı testler" for the complete "Faster tests you can actually trust" message.
