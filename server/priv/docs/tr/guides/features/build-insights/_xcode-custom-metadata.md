## Özel meta veriler {#custom-metadata}

Filtrelemeyi iyileştirmek için derlemelere ortam değişkenleriyle meta veri ekleyebilirsiniz.

### Ortam değişkenleri

| Değişken | Biçim | Açıklama |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Virgülle ayrılmış | Tek bir değişkende birden fazla etiket. |
| `TUIST_BUILD_VALUE_*` | Tek değer | Son ekin anahtar olduğu anahtar-değer çifti. |

### Örnekler

Derlemenizi çağırmadan önce bu değerleri CI sisteminizde veya kabuğunuzda ayarlayın:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
