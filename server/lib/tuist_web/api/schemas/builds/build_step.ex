defmodule TuistWeb.API.Schemas.Builds.BuildStep do
  @moduledoc "Shared step schemas, query parameters and errors for all build systems."
  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias OpenApiSpex.Schema
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  @step_properties %{
    id: %Schema{type: :string},
    title: %Schema{type: :string},
    project: %Schema{type: :string},
    target: %Schema{type: :string},
    category: %Schema{type: :string},
    start_ms: %Schema{type: :number},
    duration_ms: %Schema{type: :number},
    status: %Schema{type: :string}
  }

  def step(title),
    do: %Schema{title: title, type: :object, properties: @step_properties, required: Map.keys(@step_properties)}

  def detail(title, nullable_log) do
    %Schema{
      title: title,
      type: :object,
      properties:
        Map.merge(@step_properties, %{
          log: %Schema{type: :string, nullable: nullable_log},
          log_truncated: %Schema{type: :boolean}
        }),
      required: Map.keys(@step_properties) ++ [:log, :log_truncated]
    }
  end

  def query_parameters(statuses),
    do: [
      page: [in: :query, type: %Schema{type: :integer, minimum: 1, maximum: 100_000, default: 1}],
      page_size: [in: :query, type: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}],
      search: [
        in: :query,
        type: %Schema{type: :string, maxLength: 512},
        description: "Case-insensitive title, project, or target search."
      ],
      project: [in: :query, type: %Schema{type: :string, maxLength: 512}],
      target: [in: :query, type: %Schema{type: :string, maxLength: 512}],
      category: [
        in: :query,
        type: %Schema{type: :string, maxLength: 128},
        description: "Exact category returned by a recorded step."
      ],
      status: [in: :query, type: %Schema{type: :string, enum: statuses}],
      start_ms: [in: :query, type: %Schema{type: :number, minimum: 0}],
      end_ms: [in: :query, type: %Schema{type: :number, minimum: 0}],
      sort_by: [
        in: :query,
        type: %Schema{type: :string, enum: ["duration_ms", "start_ms"], default: "duration_ms"},
        description: "Duration descending or start time ascending; ties use step ID ascending."
      ]
    ]

  def errors,
    do: %{
      bad_request: {"Invalid step ID, filters, or time range", "application/json", Error},
      not_found: {"Build or step not found", "application/json", Error},
      forbidden: {"Access denied", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }

  def error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{message: "Build or step not found."})

  def error(conn, _reason),
    do: conn |> put_status(:bad_request) |> json(%{message: "Invalid step ID, filters, or time range."})
end
