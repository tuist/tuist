---
{
  "title": "HTTP proxy",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "HTTPS_PROXY veya HTTP_PROXY ayarlandığında Tuist'in HTTP trafiğini kurumsal bir proxy üzerinden nasıl yönlendirdiğini öğrenin."
}
---
# HTTP proxy {#http-proxy}

Ortamda `HTTPS_PROXY` veya `HTTP_PROXY` ayarlandığında, Tuist yönettiği HTTP bağlantılarını otomatik olarak bu proxy üzerinden yönlendirir. Bu durum, ek yapılandırma gerektirmeden hem Tuist CLI hem de Tuist Gradle eklentisi için geçerlidir.

Davranış, `curl`, `git` ve çoğu geliştirici aracının kullandığı gelenekle eşleşir; bu nedenle bu değişkenleri diğer araçlar için zaten ayarlayan herhangi bir ortam, Tuist ile kutudan çıkar çıkmaz çalışır.

## Neler proxy üzerinden yönlendirilir {#what-is-proxied}

Yalnızca Tuist’e ait olan HTTP istemcileri proxy üzerinden yönlendirilir:

- önbellek, önizlemeler, analitik ve kayıt defteri uç noktaları,
- ve Gradle eklentisinin Tuist hizmetlerine yaptığı çağrılar (uzak derleme önbelleği, derleme içgörüler, test içgörüler, test karantinası, test parçalama).

## Değişken arama sırası {#variable-lookup-order}

Tuist, aşağıdaki sırayla ilk boş olmayan değeri okur:

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

Değer, `http://proxy.corp:8080` gibi bir URL olmalıdır. Satır içi kimlik bilgileri (`http://user:password@proxy.corp:8080`) dikkate alınır.
