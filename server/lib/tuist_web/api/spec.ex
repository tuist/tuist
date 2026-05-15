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
  alias TuistWeb.API.Schemas.Webhook
  alias TuistWeb.Router

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
        description: description(),
        extensions: %{
          "x-logo" => %{
            "url" => "https://tuist.dev/images/open-graph/squared.png",
            "altText" => "Tuist logo"
          }
        }
      },
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

  # The list of webhook event schemas to document in the API portal.
  # Kept here so the matching `info.description` markdown lists exactly
  # the same set; a unit test cross-checks both against
  # `Tuist.Webhooks.WebhookEndpoint.event_groups/0`.
  def webhook_event_schemas, do: @webhook_event_schemas

  defp description do
    """
    ## Webhook events

    Tuist can POST event notifications to HTTPS endpoints you register on your
    account. Each delivery is a JSON envelope with `id`, `type`, `created`, and
    an event-specific `object` payload, signed via the `Tuist-Signature` header.
    See the [webhooks integration guide](https://docs.tuist.dev/en/guides/integrations/webhooks)
    for the full payload, signature verification, and retry rules.

    The supported event types and their payload shapes:

    | Event type            | When it fires                                                            | Payload schema |
    | --------------------- | ------------------------------------------------------------------------ | -------------- |
    | `test_case.created`   | A test case is observed for the first time in the account.               | [`WebhookTestCaseCreatedEvent`](#tag/Webhook-events/operation/test_case.created) |
    | `test_case.updated`   | A test case's attributes change — flakiness, state transitions, etc.     | [`WebhookTestCaseUpdatedEvent`](#tag/Webhook-events/operation/test_case.updated) |
    | `preview.created`     | A new preview is created in the account (after the build finishes upload). | [`WebhookPreviewCreatedEvent`](#tag/Webhook-events/operation/preview.created) |
    | `preview.deleted`     | A preview is removed from the account.                                   | [`WebhookPreviewDeletedEvent`](#tag/Webhook-events/operation/preview.deleted) |

    Each payload schema is registered under `components.schemas` so you can
    `$ref` it from any client generator. The envelope shape is stable across
    event types — only the `object` differs.
    """
  end
end
