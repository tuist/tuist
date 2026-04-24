defmodule TuistWeb.AgentDiscovery do
  @moduledoc false

  @api_base_path "/api"
  @api_catalog_path "/.well-known/api-catalog"
  @api_catalog_profile_uri "https://www.rfc-editor.org/info/rfc9727"
  @service_desc_path "/api/spec"
  @service_doc_path "/api/docs"

  def homepage_link_header_value do
    Enum.join(
      [
        api_catalog_link_header_value(),
        link_value(@service_desc_path, "service-desc", type: "application/json"),
        link_value(@service_doc_path, "service-doc", type: "text/html")
      ],
      ", "
    )
  end

  def api_catalog_link_header_value do
    link_value(@api_catalog_path, "api-catalog",
      type: "application/linkset+json",
      profile: @api_catalog_profile_uri
    )
  end

  def api_catalog_content_type do
    ~s(application/linkset+json; profile="#{@api_catalog_profile_uri}")
  end

  def api_catalog(origin) do
    %{
      "linkset" => [
        %{
          "anchor" => origin <> @api_base_path,
          "service-desc" => [
            %{
              "href" => origin <> @service_desc_path,
              "type" => "application/json"
            }
          ],
          "service-doc" => [
            %{
              "href" => origin <> @service_doc_path,
              "type" => "text/html"
            }
          ]
        }
      ]
    }
  end

  defp link_value(target, relation, attributes) do
    parameters =
      [{"rel", relation}] ++ Enum.map(attributes, fn {key, value} -> {Atom.to_string(key), value} end)

    IO.iodata_to_binary(["<#{target}>", Enum.map(parameters, fn {key, value} -> ~s(; #{key}="#{value}") end)])
  end
end
