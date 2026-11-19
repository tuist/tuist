### Test seçenekleri {#test-options}

| Bayrak | Ortam değişkeni | Açıklama |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Çalıştırılacak parçanın sıfır tabanlı indeksi |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Derleme aşaması tarafından üretilen kesin parça planı tanımlayıcısı. Oluşturulan sağlayıcı çıktıları bu değeri otomatik olarak içerir |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Parça planı için benzersiz tanımlayıcı (desteklenen CI sağlayıcılarında otomatik olarak türetilir) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Yerel olarak yönetilen bir parça arşivinin yolu; Tuist, test ürünlerini uzak depolamadan indirmek yerine bunu ayıklar |

Tuist `.xctestproducts` paketini indirir ve yalnızca o parçaya atanmış testleri içerecek şekilde filtreler.
