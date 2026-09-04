defmodule TuistWeb.API.BazelController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Bazel"]

  @project_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]
  @pagination_parameters [
    page_size: [
      in: :query,
      type: %Schema{type: :integer, default: 20, minimum: 1, maximum: 100},
      description: "The maximum number of results to return."
    ],
    page: [in: :query, type: %Schema{type: :integer, default: 1, minimum: 1}, description: "The page number to return."]
  ]
  @status_parameter [
    status: [
      in: :query,
      type: %Schema{type: :string, enum: ["success", "failure"]},
      description: "Filter by invocation status."
    ]
  ]
  @cache_summary_schema %Schema{
    type: :object,
    properties: %{
      hits: %Schema{type: :integer},
      misses: %Schema{type: :integer},
      download_bytes: %Schema{type: :integer},
      upload_bytes: %Schema{type: :integer},
      hit_rate: %Schema{type: :number, nullable: true}
    },
    required: [:hits, :misses, :download_bytes, :upload_bytes, :hit_rate]
  }
  @invocation_schema %Schema{
    type: :object,
    properties: %{
      invocation_id: %Schema{type: :string},
      command: %Schema{type: :string},
      status: %Schema{type: :string, enum: ["success", "failure"]},
      exit_code: %Schema{type: :integer},
      started_at: %Schema{type: :string, format: :"date-time"},
      finished_at: %Schema{type: :string, format: :"date-time"},
      duration_ms: %Schema{type: :integer},
      cache: @cache_summary_schema
    },
    required: [:invocation_id, :command, :status, :exit_code, :started_at, :finished_at, :duration_ms, :cache]
  }
  @cache_event_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      invocation_id: %Schema{type: :string},
      outcome: %Schema{type: :string, enum: ["hit", "miss", "write"]},
      action_digest: %Schema{type: :string},
      action_mnemonic: %Schema{type: :string},
      target_label: %Schema{type: :string},
      configuration_id: %Schema{type: :string},
      size: %Schema{type: :integer},
      duration_ms: %Schema{type: :integer},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :invocation_id, :outcome, :action_digest, :size, :duration_ms, :inserted_at]
  }

  operation(:list_invocations,
    summary: "List Bazel invocations for a project.",
    operation_id: "listBazelInvocations",
    parameters: @project_parameters ++ @pagination_parameters ++ @status_parameter,
    responses: %{
      ok:
        {"List of Bazel invocations", "application/json",
         %Schema{
           type: :object,
           properties: %{
             invocations: %Schema{type: :array, items: @invocation_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:invocations, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_invocations(
        %{assigns: %{selected_project: project}, params: %{page: page, page_size: page_size} = params} = conn,
        _params
      ) do
    filters = maybe_append_filter([%{field: :project_id, op: :==, value: project.id}], :status, params[:status])

    {invocations, meta} =
      Bazel.list_invocations(project.id, %{
        filters: filters,
        order_by: [:finished_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    json(conn, %{invocations: Enum.map(invocations, &invocation_json/1), pagination_metadata: pagination_json(meta)})
  end

  operation(:get_invocation,
    summary: "Get a Bazel invocation by its Bazel invocation identifier.",
    operation_id: "getBazelInvocation",
    parameters:
      @project_parameters ++
        [
          invocation_id: [
            in: :path,
            type: :string,
            required: true,
            description: "The Bazel invocation identifier."
          ]
        ],
    responses: %{
      ok: {"Bazel invocation", "application/json", @invocation_schema},
      not_found: {"Bazel invocation not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def get_invocation(%{assigns: %{selected_project: project}, params: %{invocation_id: invocation_id}} = conn, _params) do
    case Bazel.get_invocation(project.id, invocation_id) do
      {:ok, invocation} ->
        json(conn, invocation_json(invocation))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bazel invocation not found."})
    end
  end

  operation(:list_cache_events,
    summary: "List Bazel remote-cache events for a project.",
    operation_id: "listBazelCacheEvents",
    parameters:
      @project_parameters ++
        @pagination_parameters ++
        [
          invocation_id: [in: :query, type: :string, description: "Filter by Bazel invocation identifier."],
          outcome: [
            in: :query,
            type: %Schema{type: :string, enum: ["hit", "miss", "write"]},
            description: "Filter by cache outcome."
          ]
        ],
    responses: %{
      ok:
        {"List of Bazel remote-cache events", "application/json",
         %Schema{
           type: :object,
           properties: %{
             cache_events: %Schema{type: :array, items: @cache_event_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:cache_events, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_cache_events(
        %{assigns: %{selected_project: project}, params: %{page: page, page_size: page_size} = params} = conn,
        _params
      ) do
    filters =
      [%{field: :project_id, op: :==, value: project.id}]
      |> maybe_append_filter(:invocation_id, params[:invocation_id])
      |> maybe_append_filter(:outcome, params[:outcome])

    {events, meta} =
      ReapiCache.list_cache_events(project.id, %{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    json(conn, %{cache_events: Enum.map(events, &cache_event_json/1), pagination_metadata: pagination_json(meta)})
  end

  operation(:get_cache_event,
    summary: "Get a Bazel remote-cache event by its identifier.",
    operation_id: "getBazelCacheEvent",
    parameters:
      @project_parameters ++
        [
          cache_event_id: [
            in: :path,
            type: :string,
            required: true,
            description: "The Bazel cache event identifier."
          ]
        ],
    responses: %{
      ok: {"Bazel remote-cache event", "application/json", @cache_event_schema},
      not_found: {"Bazel remote-cache event not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def get_cache_event(%{assigns: %{selected_project: project}, params: %{cache_event_id: cache_event_id}} = conn, _params) do
    case ReapiCache.get_cache_event(project.id, cache_event_id) do
      {:ok, event} ->
        json(conn, cache_event_json(event))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bazel remote-cache event not found."})
    end
  end

  defp invocation_json(invocation) do
    %{
      invocation_id: invocation.invocation_id,
      command: invocation.command,
      status: invocation.status,
      exit_code: invocation.exit_code,
      started_at: invocation.started_at,
      finished_at: invocation.finished_at,
      duration_ms: invocation.duration_ms,
      cache: invocation.cache
    }
  end

  defp cache_event_json(event) do
    %{
      id: event.id,
      invocation_id: event.invocation_id,
      outcome: event.outcome,
      action_digest: event.action_digest,
      action_mnemonic: event.action_mnemonic,
      target_label: event.target_label,
      configuration_id: event.configuration_id,
      size: event.size,
      duration_ms: event.duration_ms,
      inserted_at: event.inserted_at
    }
  end

  defp pagination_json(meta) do
    %{
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      current_page: meta.current_page,
      page_size: meta.page_size,
      total_count: meta.total_count,
      total_pages: meta.total_pages
    }
  end

  defp maybe_append_filter(filters, _field, nil), do: filters
  defp maybe_append_filter(filters, _field, ""), do: filters
  defp maybe_append_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]
end
