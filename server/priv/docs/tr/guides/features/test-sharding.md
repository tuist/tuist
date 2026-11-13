---
{
  "title": "Test Parçalama",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile test süitinizi hızlandırmak için testleri birden fazla CI çalıştırıcısına dağıtın."
}
---
# Test Parçalama {#test-sharding}

Modern CI sunucuları, testlerin bir dereceye kadar paralel çalıştırılmasına olanak tanıyan çok çekirdekli ortamlar sunar. Ancak, tek bir sunucunun sunduklarının ötesine geçmeniz gereken senaryolar vardır — örneğin, aynı anda çalıştırabileceğiniz simülatör sayısıyla sınırlı olduğunuzda veya test paketiniz tek bir makinenin kapasitesini aştığında.

Bu durumlarda, testleri birden fazla CI çalıştırıcısına dağıtan ve sonuçları tek bir görünümde toplayan bir sisteme ihtiyacınız vardır. Test parçalama tam olarak bunu yapar.

Tuist, her çalıştırıcının yaklaşık aynı zamanda bitirmesini sağlamak için [bin-packing algoritması](https://en.wikipedia.org/wiki/Bin_packing_problem) kullanarak yükü parçalar arasında akıllıca dengeler ve bunun için geçmiş test zamanlama verilerini kullanır. Tüm parçalardan gelen sonuçlar <.localized_link href="/guides/features/test-insights">Test İçgörülerinde</.localized_link> otomatik olarak toplanır ve tüm parçalar genelinde test paketinizin tek bir birleşik görünümünü sunar. Parçalama, duvar saati süresini kısaltır ancak makine süresini artırabilir; ikisini nasıl değerlendireceğinizi [Yavaş testler](https://tuist.dev/solutions/slow-tests) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) açıklar.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode testlerini paralel CI çalıştırıcılarına dağıtın."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist tarafından oluşturulan projelerdeki testleri paralel CI çalıştırıcılarına dağıtın."
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle testlerini paralel CI çalıştırıcılarına dağıtın."
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixir projenizin testlerini paralel CI çalıştırıcılarına dağıtın."
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargo test hedeflerini paralel CI çalışanlarına dağıtın."
    link="/guides/features/test-sharding/rust"
/>
  <.home_card
    title="Once"
    details="Keşfedilen Once test gruplarını, barındırılan bir plan ve birleştirilmiş sonuçlarla CI çalışanlarına dağıtın."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
