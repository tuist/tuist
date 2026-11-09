---
{
  "title": "Test Parçalama",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile test paketinizi hızlandırmak için testleri birden fazla CI çalıştırıcısına dağıtın."
}
---
# Test Bölümlere Ayırma {#test-sharding}

Modern CI sunucuları, test paralelleştirmesine belirli ölçüde izin veren çok çekirdekli ortamlar sunar. Ancak tek bir sunucunun sunduklarının ötesine geçmeniz gereken senaryolar vardır; örneğin, aynı anda çalıştırabileceğiniz simülatör sayısıyla sınırlı olduğunuzda veya test paketiniz tek bir makinenin kapasitesini aştığında.

Bu durumlarda, testleri birden fazla CI çalıştırıcısına dağıtan ve sonuçları tek bir görünümde birleştiren bir sisteme ihtiyacınız vardır. Test bölümlere ayırma tam olarak bunu yapar.

Tuist, geçmiş test zamanlama verilerini kullanarak yükü parçalar arasında akıllıca dengeler ve bunun için bir [bin-packing algoritması](https://en.wikipedia.org/wiki/Bin_packing_problem) kullanır; böylece her çalıştırıcı yaklaşık aynı zamanda tamamlanır. Tüm parçalardan gelen sonuçlar otomatik olarak <.localized_link href="/guides/features/test-insights">Test İçgörülerinde</.localized_link> birleştirilir ve size tüm parçalar genelinde test paketinizin tek ve birleşik bir görünümünü sunar.

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcode testlerini paralel CI çalıştırıcılarına bölün."
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Oluşturulan projeler"
    details="Tuist tarafından oluşturulan projelerdeki testleri paralel CI çalıştırıcılarına bölün."
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
    title="Once"
    details="Keşfedilen Once test gruplarını barındırılan bir planla CI işçilerine dağıtın ve sonuçları birleştirin."
    link="/guides/features/test-sharding/once"
/>
</.home_cards>
