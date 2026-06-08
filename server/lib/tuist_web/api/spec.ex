defmodule TuistWeb.API.Spec do
  @moduledoc ~S"""
  A module that contains the spec of the Tuist API.
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Tag
  alias Tuist.Webhooks.WebhookEndpoint
  alias TuistWeb.API.Schemas.Webhook
  alias TuistWeb.Router

  @webhook_events_tag "Webhook events"

  # Authoritative mapping from event-type string to envelope schema module.
  # Adding a new event means adding it here AND to
  # `WebhookEndpoint.event_groups/0`; the compile-time assertion below
  # tightens that link so the two lists can't drift.
  @webhook_event_schemas %{
    "test_case.created" => Webhook.TestCaseCreatedEvent,
    "test_case.updated" => Webhook.TestCaseUpdatedEvent,
    "preview.created" => Webhook.PreviewCreatedEvent,
    "preview.deleted" => Webhook.PreviewDeletedEvent
  }

  # Supporting types referenced from the event envelopes via `object:`.
  # Listed explicitly so `add_schemas/2` registers them alongside the
  # events — they aren't reachable from any HTTP route either.
  @webhook_supporting_schemas [Webhook.TestCase, Webhook.Preview]

  @catalog_event_types WebhookEndpoint.event_groups()
                       |> Enum.flat_map(& &1.events)
                       |> Enum.map(& &1.type)

  if MapSet.new(@catalog_event_types) != MapSet.new(Map.keys(@webhook_event_schemas)) do
    raise """
    `@webhook_event_schemas` in #{__MODULE__} is out of sync with
    `Tuist.Webhooks.WebhookEndpoint.event_groups/0`. Catalog: #{inspect(@catalog_event_types)}, schemas: #{inspect(Map.keys(@webhook_event_schemas))}.
    """
  end

  # Built at compile time from `Tuist.Webhooks.WebhookEndpoint.event_groups/0`
  # so the docs table can't drift from the event catalog. The schema title
  # is read from each module's `schema().title` rather than mangled from
  # the event-type string, so renaming a schema only requires touching
  # the schema module itself.
  @webhook_events_table_rows WebhookEndpoint.event_groups()
                             |> Enum.flat_map(& &1.events)
                             |> Enum.map_join("\n", fn %{type: type, description: description} ->
                               title = Map.fetch!(@webhook_event_schemas, type).schema().title
                               "| `#{type}` | #{description} | [`#{title}`](#section/Schemas/#{title}) |"
                             end)

  @webhook_events_description """
  Tuist can POST event notifications to HTTPS endpoints you register on your
  account. Each delivery is a JSON envelope with `id`, `type`, `created`, and
  an event-specific `object` payload, signed via the `Tuist-Signature` header.
  See the [webhooks integration guide](https://tuist.dev/en/docs/guides/integrations/webhooks)
  for the full payload, signature verification, and retry rules.

  The supported event types and their payload shapes:

  | Event type | When it fires | Payload schema |
  | --- | --- | --- |
  #{@webhook_events_table_rows}

  Each payload schema is registered under `components.schemas` so you can
  `$ref` it from any client generator. The envelope shape is stable across
  event types — only the `object` differs.
  """

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [],
      info: %Info{
        title: "Tuist",
        version: "0.1.0",
        extensions: %{
          "x-logo" => %{
            "url" => "https://tuist.dev/images/open-graph/squared.png",
            "altText" => "Tuist logo"
          }
        }
      },
      tags: [
        %Tag{
          name: @webhook_events_tag,
          description: @webhook_events_description
        }
      ],
      components: %Components{
        securitySchemes: %{
          "authorization" => %SecurityScheme{type: "http", scheme: "bearer"},
          "cookie" => %SecurityScheme{type: "apiKey", in: "cookie", name: "_tuist_cloud_key"},
          "oauth2" => %SecurityScheme{
            type: "oauth2",
            flows: %{
              authorizationCode: %{
                authorizationUrl: "/oauth2/authorize",
                tokenUrl: "/oauth2/token",
                scopes: %{
                  "read" => "Read access to resources",
                  "write" => "Write access to resources"
                }
              }
            }
          }
        }
      },
      security: [%{"authorization" => []}, %{"cookie" => []}],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
    |> OpenApiSpex.add_schemas(Map.values(@webhook_event_schemas) ++ @webhook_supporting_schemas)
  end
end
