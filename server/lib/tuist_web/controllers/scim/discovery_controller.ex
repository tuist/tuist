defmodule TuistWeb.SCIM.DiscoveryController do
  @moduledoc """
  SCIM 2.0 service discovery endpoints (RFC 7644 §4).
  """
  use TuistWeb, :controller

  import TuistWeb.SCIM.Helpers

  alias Tuist.SCIM.Resource

  def service_provider_config(conn, _params) do
    body = %{
      schemas: ["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
      documentationUri: "https://docs.tuist.dev",
      patch: %{supported: true},
      bulk: %{supported: false, maxOperations: 0, maxPayloadSize: 0},
      filter: %{supported: true, maxResults: 200},
      changePassword: %{supported: false},
      sort: %{supported: false},
      etag: %{supported: false},
      authenticationSchemes: [
        %{
          type: "oauthbearertoken",
          name: "OAuth Bearer Token",
          description: "Per-organization SCIM bearer token issued in Tuist organization settings.",
          specUri: "https://datatracker.ietf.org/doc/html/rfc6750",
          documentationUri: "https://docs.tuist.dev",
          primary: true
        }
      ],
      meta: %{
        resourceType: "ServiceProviderConfig",
        location: "#{conn.assigns.scim_base_url}/ServiceProviderConfig"
      }
    }

    send_scim_json(conn, 200, body)
  end

  def resource_types(conn, _params) do
    base = conn.assigns.scim_base_url

    resources = [
      %{
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],
        id: "User",
        name: "User",
        endpoint: "/Users",
        description: "User Account",
        schema: Resource.user_schema(),
        meta: %{location: "#{base}/ResourceTypes/User", resourceType: "ResourceType"}
      },
      %{
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],
        id: "Group",
        name: "Group",
        endpoint: "/Groups",
        description: "Group",
        schema: Resource.group_schema(),
        meta: %{location: "#{base}/ResourceTypes/Group", resourceType: "ResourceType"}
      }
    ]

    send_scim_json(conn, 200, %{
      schemas: [Resource.list_schema()],
      totalResults: length(resources),
      Resources: resources
    })
  end

  def schemas(conn, _params) do
    send_scim_json(conn, 200, %{
      schemas: [Resource.list_schema()],
      totalResults: 2,
      Resources: [user_schema_doc(), group_schema_doc()]
    })
  end

  def schema(conn, %{"id" => id}) do
    cond do
      id == Resource.user_schema() -> send_scim_json(conn, 200, user_schema_doc())
      id == Resource.group_schema() -> send_scim_json(conn, 200, group_schema_doc())
      true -> send_scim_error(conn, 404, "Schema not found")
    end
  end

  defp user_schema_doc do
    %{
      id: Resource.user_schema(),
      name: "User",
      description: "User Account",
      attributes: [
        attr("userName", "string", true, "server", true, "always"),
        attr("displayName", "string", false, "none", false, "default"),
        attr("active", "boolean", false, "none", false, "default"),
        complex_attr("emails", [
          attr("value", "string", false, "none", false, "default"),
          attr("primary", "boolean", false, "none", false, "default"),
          attr("type", "string", false, "none", false, "default")
        ])
      ],
      meta: %{resourceType: "Schema", location: "/scim/v2/Schemas/#{Resource.user_schema()}"}
    }
  end

  defp group_schema_doc do
    %{
      id: Resource.group_schema(),
      name: "Group",
      description: "Group",
      attributes: [
        attr("displayName", "string", true, "none", false, "default"),
        complex_attr("members", [
          attr("value", "string", false, "none", false, "immutable"),
          attr("display", "string", false, "none", false, "default")
        ])
      ],
      meta: %{resourceType: "Schema", location: "/scim/v2/Schemas/#{Resource.group_schema()}"}
    }
  end

  defp attr(name, type, required, uniqueness, case_exact, returned) do
    %{
      name: name,
      type: type,
      multiValued: false,
      required: required,
      caseExact: case_exact,
      mutability: "readWrite",
      returned: returned,
      uniqueness: uniqueness
    }
  end

  defp complex_attr(name, sub_attributes) do
    %{
      name: name,
      type: "complex",
      multiValued: true,
      required: false,
      mutability: "readWrite",
      returned: "default",
      subAttributes: sub_attributes
    }
  end
end
