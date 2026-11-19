---
{
  "title": "Test Parçalama",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile test paketinizi hızlandırmak için testleri birden fazla CI çalıştırıcısına dağıtın."
}
---
# Test Bölümleme {#test-sharding}

Modern CI sunucuları, test paralelleştirmesine belirli ölçüde olanak tanıyan çok çekirdekli ortamlar sunar. Ancak tek bir sunucunun sağlayabileceğinin ötesine geçmeniz gereken senaryolar vardır; örneğin, aynı anda çalıştırabileceğiniz simülatör sayısıyla sınırlıysanız veya test paketiniz tek bir makinenin kapasitesini aşıyorsa.

Bu durumlarda, testleri birden fazla CI çalıştırıcısına dağıtan ve sonuçları tekrar birleşik bir görünümde toplayan bir sisteme ihtiyacınız vardır. Test bölümleme tam olarak bunu yapar.

Tuist, her çalıştırıcının yaklaşık aynı zamanda bitirmesini sağlamak için yükü bölümler arasında akıllıca dengelemek amacıyla geçmiş test zamanlama verilerini ve bir [bin-packing algoritması](https://en.wikipedia.org/wiki/Bin_packing_problem) kullanır. Tüm bölümlerden gelen sonuçlar <.localized_link href="/guides/features/test-insights">Test İçgörülerinde</.localized_link> otomatik olarak toplanır ve size tüm bölümlerdeki test paketinizin tek bir birleşik görünümünü sunar. Bölümleme takvim süresini kısaltır ancak makine süresini artırabilir; [Yavaş testler](https://tuist.dev/solutions/slow-tests) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) bu ikisi arasındaki dengeyi nasıl kuracağınızı açıklar.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode testlerini paralel CI çalıştırıcılarına bölün."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist ile oluşturulan projelerdeki testleri paralel CI çalıştırıcılarına bölün."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle testlerini paralel CI çalıştırıcılarına bölün."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixir projenizin testlerini paralel CI çalıştırıcılarına bölün."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo test hedeflerini paralel CI işçilerine dağıtın."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="Keşfedilen Struo test gruplarını barındırılan bir plan ve birleştirilmiş sonuçlarla CI işçilerine dağıtın."
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
