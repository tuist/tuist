## CI'da derleme içgörüleri {#continuous-integration}

CI'daki derleme içgörülerini izlemek için CI'ın <.localized_link href="/guides/server/authentication#continuous-integration">kimliği doğrulanmış</.localized_link> olduğundan emin olun.

Xcodebuild tarafından yönlendirilen CI için şunları yapmanız gerekir:
- `xcodebuild` eylemlerini çağırırken <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> kullanın.
- `xcodebuild` komutunuza `-resultBundlePath` ekleyin.

`-resultBundlePath` olmadan gerekli etkinlik günlükleri ve sonuç paketleri oluşturulmaz ve `tuist inspect build` derlemeyi analiz edemez.
