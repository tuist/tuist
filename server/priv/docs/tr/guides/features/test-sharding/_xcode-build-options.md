### Derleme seçenekleri {#build-options}

| Bayrak | Ortam değişkeni | Açıklama |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Maksimum parça sayısı. Parça sayısını sınırlamak için `--shard-max-duration` ile birlikte kullanılır |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Minimum parça sayısı |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Tam parça sayısı (`--shard-min`/`--shard-max` ile birbirini dışlar). Paket granülerliğinde son parça tüm kalanları kapsar |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Parça başına hedeflenen maksimum süre (milisaniye cinsinden) |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (varsayılan) tüm test modüllerini parçalara dağıtır; `suite` daha ince dengeli dağıtım için tekil test sınıflarını dağıtır |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Parça planı için benzersiz tanımlayıcı (desteklenen CI sağlayıcılarında otomatik olarak türetilir) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist’in, test ürünlerini uzak depolamaya yüklemek yerine optimize edilmiş parça arşivini yazdığı yol |
