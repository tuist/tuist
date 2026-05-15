defmodule TuistWeb.API.CliSpec do
  @moduledoc """
  Slim OpenAPI spec used by the CLI Swift codegen.

  Wraps `TuistWeb.API.Spec` and strips webhook-event extras — those
  schemas exist purely to document the dashboard's outbound webhook
  contract on `/api/docs`, the CLI never calls them, and Swift OpenAPI
  Generator would otherwise bloat `Types.swift` with unused types and
  splat the spec's `info.description` markdown onto the `Client` struct.

  Consumed by `server/mise/tasks/generate-api-cli-code.sh`.
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.Info
  alias TuistWeb.API.Spec

  @impl OpenApiSpex.OpenApi
  def spec do
    base = Spec.spec()

    webhook_schema_titles =
      Spec.webhook_event_schemas()
      |> Enum.map(& &1.schema().title)
      |> MapSet.new()

    components = %{
      base.components
      | schemas: Map.reject(base.components.schemas, fn {title, _} -> title in webhook_schema_titles end)
    }

    %{base | components: components, info: cli_info(base.info)}
  end

  # Strip the markdown description — `mix openapi.spec.yaml` carries it
  # through to the CLI's `Client.swift` doc comment, where a section
  # about outbound webhooks reads as nonsense.
  defp cli_info(%Info{} = info), do: %{info | description: nil}
end
