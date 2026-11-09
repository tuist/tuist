### Test seçenekleri {#test-options}

| Bayrak | Ortam değişkeni | Açıklama |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Çalıştırılacak shard'ın sıfır tabanlı indeksi |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Derleme aşaması tarafından üretilen tam shard planı tanımlayıcısı. Oluşturulan sağlayıcı çıktıları bu değeri otomatik olarak içerir |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Shard planı için benzersiz tanımlayıcı (desteklenen CI sağlayıcılarında otomatik olarak türetilir) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Yerel olarak yönetilen bir shard arşivinin yolu; Tuist, test ürünlerini uzak depolamadan indirmek yerine bunu çıkarır |

Tuist `.xctestproducts` paketini indirir ve yalnızca o shard'a atanmış testleri içerecek şekilde filtreler.
