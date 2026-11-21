---
{
  "title": "Test Parçalama",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile test paketinizi hızlandırmak için testleri birden fazla CI çalıştırıcısına dağıtın."
}
---
# Test Shardlama {#test-sharding}

Modern CI sunucuları, testlerin belirli düzeyde paralelleştirilmesine olanak tanıyan çok çekirdekli ortamlar sunar. Ancak, tek bir sunucunun sunduklarının ötesine geçmeniz gereken senaryolar vardır — örneğin, aynı anda çalıştırabileceğiniz simülatör sayısıyla sınırlı olduğunuzda veya test paketiniz tek bir makinenin kapasitesini aştığında.

Bu durumlarda, testleri birden fazla CI çalıştırıcısına dağıtan ve sonuçları tek bir görünümde birleştiren bir sisteme ihtiyacınız vardır. Test shardlama tam olarak bunu yapar.

Tuist, her çalıştırıcının yaklaşık aynı anda bitirmesini sağlamak için yükü shardlar arasında akıllıca dengelemek üzere geçmiş test zamanlama verilerini ve bir [bin-packing algoritması](https://en.wikipedia.org/wiki/Bin_packing_problem) kullanır. Tüm shardlardan gelen sonuçlar <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> içinde otomatik olarak birleştirilir ve tüm shardlar boyunca test paketinizin tek bir birleşik görünümünü sunar. Shardlama duvar saati süresini kısaltır ancak makine süresini artırabilir; [Yavaş testler](https://tuist.dev/solutions/slow-tests) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) bu ikisi arasındaki dengeyi nasıl kuracağınızı açıklar.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode testlerini paralel CI çalıştırıcılarına shardlayın."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist tarafından oluşturulan projelerdeki testleri paralel CI çalıştırıcılarına shardlayın."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle testlerini paralel CI çalıştırıcılarına shardlayın."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixir projenizin testlerini paralel CI çalıştırıcılarına shardlayın."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo test hedeflerini paralel CI çalışanlarına dağıtın."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Struo"
    details="Barındırılan bir planla ve birleştirilmiş sonuçlarla keşfedilen Struo test yığınlarını CI çalışanlarına dağıtın."
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
