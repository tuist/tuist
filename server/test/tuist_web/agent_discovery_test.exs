defmodule TuistWeb.AgentDiscoveryTest do
  use ExUnit.Case, async: true

  alias TuistWeb.AgentDiscovery

  test "returns the homepage link header value" do
    assert AgentDiscovery.homepage_link_header_value() ==
             ~s(</.well-known/api-catalog>; rel="api-catalog"; type="application/linkset+json"; profile="https://www.rfc-editor.org/info/rfc9727", </api/spec>; rel="service-desc"; type="application/json", </api/docs>; rel="service-doc"; type="text/html")
  end

  test "returns the api catalog link header value" do
    assert AgentDiscovery.api_catalog_link_header_value() ==
             ~s(</.well-known/api-catalog>; rel="api-catalog"; type="application/linkset+json"; profile="https://www.rfc-editor.org/info/rfc9727")
  end

  test "returns the api catalog content type" do
    assert AgentDiscovery.api_catalog_content_type() ==
             ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
  end

  test "returns the api catalog body" do
    assert AgentDiscovery.api_catalog("https://tuist.dev") == %{
             "linkset" => [
               %{
                 "anchor" => "https://tuist.dev/api",
                 "service-desc" => [
                   %{
                     "href" => "https://tuist.dev/api/spec",
                     "type" => "application/json"
                   }
                 ],
                 "service-doc" => [
                   %{
                     "href" => "https://tuist.dev/api/docs",
                     "type" => "text/html"
                   }
                 ]
               }
             ]
           }
  end
end
