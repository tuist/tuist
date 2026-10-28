defmodule TuistWeb.API.Schemas.BuildEntity do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  def entity(title) do
    %Schema{
      title: title,
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Stable project-scoped identity, independent of a run."},
        name: %Schema{type: :string},
        observations: %Schema{type: :integer, description: "Recorded observations in the list's selected cohort."},
        identity: %Schema{type: :object, additionalProperties: %Schema{type: :string}},
        first_seen_at: timestamp(),
        last_seen_at: timestamp()
      },
      required: [:id, :name, :identity, :first_seen_at, :last_seen_at]
    }
  end

  def metrics do
    %Schema{
      type: :object,
      properties: %{
        observations: %Schema{type: :integer},
        hits: %Schema{type: :integer},
        misses: %Schema{type: :integer},
        failures: %Schema{type: :integer},
        duration_samples: %Schema{
          type: :integer,
          minimum: 0,
          description: "Number of observations with a recorded duration, including genuine zero durations."
        },
        hit_rate: nullable_number("Percentage of known cache lookups that hit; unavailable without recorded lookups."),
        avg_duration_ms: nullable_number("Average recorded duration in milliseconds."),
        p50_duration_ms: nullable_number("Median recorded duration in milliseconds."),
        p90_duration_ms: nullable_number("90th percentile recorded duration in milliseconds."),
        p99_duration_ms: nullable_number("99th percentile recorded duration in milliseconds.")
      },
      required: [
        :observations,
        :hits,
        :misses,
        :failures,
        :hit_rate,
        :avg_duration_ms,
        :p50_duration_ms,
        :p90_duration_ms,
        :p99_duration_ms
      ]
    }
  end

  def analytics do
    %Schema{
      type: :object,
      properties: %{
        total: metrics(),
        previous: metrics(),
        points: %Schema{
          type: :array,
          items: %{metrics() | properties: Map.put(metrics().properties, :date, %Schema{type: :string})}
        }
      },
      required: [:total, :previous, :points]
    }
  end

  def observation(title) do
    %Schema{
      title: title,
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        parent_id: %Schema{type: :string, description: "Recorded build, invocation or command identifier."},
        execution_id: %Schema{type: :string, description: "Native execution identifier for drill-down."},
        cache_status: %Schema{type: :string, description: "Observed cache result; none means no recorded cache lookup."},
        status: %Schema{type: :string, description: "Recorded outcome; unknown does not imply success."},
        duration_ms: nullable_number("Recorded duration; cache-operation time is not compilation time."),
        git_branch: %Schema{type: :string},
        git_commit_sha: %Schema{type: :string},
        is_ci: %Schema{type: :boolean, nullable: true},
        observed_at: timestamp()
      },
      required: [
        :id,
        :parent_id,
        :execution_id,
        :status,
        :cache_status,
        :duration_ms,
        :git_branch,
        :git_commit_sha,
        :is_ci,
        :observed_at
      ]
    }
  end

  def operation(action, resource) do
    singular = resource.singular
    plural = resource.plural
    title = resource.title

    parameters = [
      account_handle: [in: :path, type: :string, required: true],
      project_handle: [in: :path, type: :string, required: true]
    ]

    parameters =
      if action == :index do
        parameters ++ [q: [in: :query, type: :string, description: "Search names and identity."]]
      else
        parameters ++ [{resource.id_param, [in: :path, type: :string, required: true]}]
      end

    parameters =
      parameters ++
        [
          start_at: [in: :query, type: :string, description: "Inclusive ISO 8601 start, within the last 90 days."],
          end_at: [in: :query, type: :string, description: "Exclusive ISO 8601 end, defaulting to now."],
          environment: [in: :query, type: %Schema{type: :string, enum: ["any", "ci", "local"], default: "any"}],
          branch: [in: :query, type: :string, description: "Exact recorded branch."]
        ]

    parameters =
      if action == :show do
        parameters
      else
        parameters ++
          [
            page: [in: :query, type: %Schema{type: :integer, default: 1, minimum: 1, maximum: 10_000}],
            page_size: [in: :query, type: %Schema{type: :integer, default: 20, minimum: 1, maximum: 100}]
          ]
      end

    parameters =
      if action == :history do
        parameters ++
          [
            after: [
              in: :query,
              type: %Schema{type: :string, maxLength: 512},
              description: "Opaque cursor for the next history page."
            ],
            before: [
              in: :query,
              type: %Schema{type: :string, maxLength: 512},
              description: "Opaque cursor for the previous history page."
            ]
          ]
      else
        parameters
      end

    {summary, _suffix, response} =
      case action do
        :index ->
          {"List #{resource.label} across builds.", plural,
           %Schema{
             type: :object,
             properties: %{
               plural => %Schema{type: :array, items: entity(title)},
               :pagination_metadata => PaginationMetadata
             },
             required: [plural, :pagination_metadata]
           }}

        :show ->
          {"Get #{resource.label_singular} and its analytics across builds.", singular,
           %Schema{
             type: :object,
             properties: %{singular => entity(title), :analytics => analytics()},
             required: [singular, :analytics]
           }}

        :history ->
          {"List recorded history for #{resource.label_singular} across builds.", :history,
           %Schema{
             type: :object,
             properties: %{
               resource.history_key => %Schema{type: :array, items: observation(title <> "Observation")},
               :pagination_metadata => history_pagination()
             },
             required: [resource.history_key, :pagination_metadata]
           }}
      end

    [
      summary: summary,
      operation_id: operation_id(action, title),
      parameters: parameters,
      responses: %{
        ok: {summary, "application/json", response},
        bad_request: {"Invalid filters", "application/json", Error},
        not_found: {"Not found in this project", "application/json", Error},
        forbidden: {"You don't have permission to access this resource", "application/json", Error},
        service_unavailable: {"Analytics query exceeded the server's resource limits", "application/json", Error},
        too_many_requests: Responses.authorization_throttled()
      }
    ]
  end

  defp history_pagination do
    schema = PaginationMetadata.schema()

    properties =
      schema.properties
      |> Map.put(:current_page, %Schema{type: :integer, nullable: true})
      |> Map.put(:after, %Schema{type: :string, nullable: true})
      |> Map.put(:before, %Schema{type: :string, nullable: true})

    %{schema | title: "BuildHistoryPagination", properties: properties}
  end

  defp operation_id(:index, title), do: "listProject#{title}s"
  defp operation_id(:show, title), do: "getProject#{title}"
  defp operation_id(:history, title), do: "listProject#{title}History"

  defp timestamp, do: %Schema{type: :string, format: :"date-time"}
  defp nullable_number(description), do: %Schema{type: :number, nullable: true, description: description}
end
