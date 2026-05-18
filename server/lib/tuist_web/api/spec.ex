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
  alias TuistWeb.API.Schemas.Webhook
  alias TuistWeb.Router

  @webhook_events_tag "Webhook events"

  # Webhook event schemas aren't reachable from any HTTP route, so the
  # router-driven `resolve_schema_modules/1` walk doesn't pick them up.
  # `add_schemas/2` is the documented escape hatch for this exact shape
  # — see `OpenApiSpex.add_schemas/2`.
  @webhook_event_schemas [
    Webhook.TestCase,
    Webhook.Preview,
    Webhook.TestCaseCreatedEvent,
    Webhook.TestCaseUpdatedEvent,
    Webhook.PreviewCreatedEvent,
    Webhook.PreviewDeletedEvent
  ]

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
          description: webhook_events_description()
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
    |> OpenApiSpex.add_schemas(@webhook_event_schemas)
  end

  # Lives on a top-level OpenAPI tag (not on `info.description`)
  # because Swift OpenAPI Generator splats `info.description` onto
  # the generated `Client.swift` as a leading docblock — which makes
  # no sense on an HTTP client struct. Redoc still renders this
  # block as a sidebar section.
  defp webhook_events_description do
    """
    Tuist can POST event notifications to HTTPS endpoints you register on your
    account. Each delivery is a JSON envelope with `id`, `type`, `created`, and
    an event-specific `object` payload, signed via the `Tuist-Signature` header.
    See the [webhooks integration guide](https://docs.tuist.dev/en/guides/integrations/webhooks)
    for the full payload, signature verification, and retry rules.

    The supported event types and their payload shapes:

    | Event type            | When it fires                                                              | Payload schema |
    | --------------------- | -------------------------------------------------------------------------- | -------------- |
    | `test_case.created`   | A test case is observed for the first time in the account.                 | [`WebhookTestCaseCreatedEvent`](#section/Schemas/WebhookTestCaseCreatedEvent) |
    | `test_case.updated`   | A test case's attributes change — flakiness, state transitions, etc.       | [`WebhookTestCaseUpdatedEvent`](#section/Schemas/WebhookTestCaseUpdatedEvent) |
    | `preview.created`     | A new preview is created in the account (after the build finishes upload). | [`WebhookPreviewCreatedEvent`](#section/Schemas/WebhookPreviewCreatedEvent) |
    | `preview.deleted`     | A preview is removed from the account.                                     | [`WebhookPreviewDeletedEvent`](#section/Schemas/WebhookPreviewDeletedEvent) |

    Each payload schema is registered under `components.schemas` so you can
    `$ref` it from any client generator. The envelope shape is stable across
    event types — only the `object` differs.
    """
  end
end
