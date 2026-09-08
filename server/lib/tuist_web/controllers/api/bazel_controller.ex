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
  @build_metrics_schema %Schema{
    type: :object,
    description: "Build metrics reported by Bazel.",
    properties: %{
      cpu_time_ms: %Schema{type: :integer, description: "Total central processing unit time in milliseconds."},
      actions_created: %Schema{
        type: :integer,
        description: "Actions Bazel created while analyzing the requested targets."
      },
      actions_executed: %Schema{
        type: :integer,
        description: "Actions Bazel executed, including remote cache hits and excluding local action-cache hits."
      },
      targets_configured: %Schema{type: :integer, description: "Targets Bazel configured."},
      packages_loaded: %Schema{type: :integer, description: "Packages Bazel loaded."}
    },
    required: [
      :cpu_time_ms,
      :actions_created,
      :actions_executed,
      :targets_configured,
      :packages_loaded
    ]
  }
  @build_timeline_schema %Schema{
    type: :object,
    nullable: true,
    description: "A bounded timeline containing the analysis phase and up to the 32 longest published actions.",
    properties: %{
      duration_ms: %Schema{type: :integer},
      lanes: %Schema{type: :array, items: %Schema{type: :string}},
      spans: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            lane: %Schema{type: :integer},
            start_ms: %Schema{type: :integer},
            duration_ms: %Schema{type: :integer},
            category: %Schema{type: :string, enum: ["analysis", "execution"]},
            description: %Schema{type: :string}
          },
          required: [:lane, :start_ms, :duration_ms, :category, :description]
        }
      }
    },
    required: [:duration_ms, :lanes, :spans]
  }
  @critical_path_schema %Schema{
    type: :object,
    nullable: true,
    description: "The critical path reported by Bazel, bounded to 32 actions.",
    properties: %{
      duration_ms: %Schema{type: :integer},
      actions: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            description: %Schema{type: :string},
            duration_ms: %Schema{type: :integer}
          },
          required: [:description, :duration_ms]
        }
      }
    },
    required: [:duration_ms, :actions]
  }
  @invocation_schema %Schema{
    type: :object,
    properties: %{
      invocation_id: %Schema{type: :string},
      command: %Schema{type: :string},
      target_patterns: %Schema{type: :array, items: %Schema{type: :string}},
      git_branch: %Schema{type: :string},
      git_commit_sha: %Schema{type: :string},
      is_ci: %Schema{type: :boolean},
      bazel_version: %Schema{type: :string},
      cache_endpoint: %Schema{type: :string},
      status: %Schema{type: :string, enum: ["success", "failure"]},
      exit_code: %Schema{type: :integer},
      started_at: %Schema{type: :string, format: :"date-time"},
      finished_at: %Schema{type: :string, format: :"date-time"},
      duration_ms: %Schema{type: :integer},
      build_metrics: @build_metrics_schema,
      build_timeline: @build_timeline_schema,
      critical_path: @critical_path_schema,
      cache: @cache_summary_schema
    },
    required: [
      :invocation_id,
      :command,
      :target_patterns,
      :git_branch,
      :git_commit_sha,
      :is_ci,
      :bazel_version,
      :cache_endpoint,
      :status,
      :exit_code,
      :started_at,
      :finished_at,
      :duration_ms,
      :build_metrics,
      :build_timeline,
      :critical_path,
      :cache
    ]
  }
  @invocation_log_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      invocation_id: %Schema{type: :string},
      sequence_number: %Schema{type: :integer},
      stream: %Schema{type: :string},
      message: %Schema{type: :string},
      observed_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :invocation_id, :sequence_number, :stream, :message, :observed_at]
  }
  @cache_event_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      invocation_id: %Schema{type: :string},
      client_kind: %Schema{type: :string},
      operation: %Schema{type: :string, enum: ["action_cache", "cas"]},
      outcome: %Schema{type: :string, enum: ["hit", "miss", "write"]},
      action_digest: %Schema{type: :string},
      action_mnemonic: %Schema{type: :string},
      target_label: %Schema{type: :string},
      configuration_id: %Schema{type: :string},
      size: %Schema{type: :integer},
      duration_ms: %Schema{type: :integer},
      cache_endpoint: %Schema{type: :string},
      observed_at: %Schema{type: :string, format: :"date-time"},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :invocation_id,
      :client_kind,
      :operation,
      :outcome,
      :action_digest,
      :action_mnemonic,
      :target_label,
      :configuration_id,
      :size,
      :duration_ms,
      :cache_endpoint,
      :observed_at,
      :inserted_at
    ]
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

  operation(:list_invocation_logs,
    summary: "List the sanitized logs captured for a Bazel invocation.",
    operation_id: "listBazelInvocationLogs",
    parameters:
      @project_parameters ++
        @pagination_parameters ++
        [
          invocation_id: [
            in: :path,
            type: :string,
            required: true,
            description: "The Bazel invocation identifier."
          ]
        ],
    responses: %{
      ok:
        {"List of Bazel invocation logs", "application/json",
         %Schema{
           type: :object,
           properties: %{
             logs: %Schema{type: :array, items: @invocation_log_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:logs, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_invocation_logs(
        %{
          assigns: %{selected_project: project},
          params: %{invocation_id: invocation_id, page: page, page_size: page_size}
        } = conn,
        _params
      ) do
    {logs, meta} =
      Bazel.list_invocation_logs(project.id, invocation_id, %{
        order_by: [:sequence_number],
        order_directions: [:asc],
        page: page,
        page_size: page_size
      })

    json(conn, %{logs: Enum.map(logs, &invocation_log_json/1), pagination_metadata: pagination_json(meta)})
  end

  operation(:get_invocation_log,
    summary: "Get one sanitized log captured for a Bazel invocation.",
    operation_id: "getBazelInvocationLog",
    parameters:
      @project_parameters ++
        [
          invocation_id: [
            in: :path,
            type: :string,
            required: true,
            description: "The Bazel invocation identifier."
          ],
          invocation_log_id: [
            in: :path,
            type: %Schema{type: :string, format: :uuid},
            required: true,
            description: "The invocation log identifier."
          ]
        ],
    responses: %{
      ok: {"Bazel invocation log", "application/json", @invocation_log_schema},
      not_found: {"Bazel invocation log not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def get_invocation_log(
        %{
          assigns: %{selected_project: project},
          params: %{invocation_id: invocation_id, invocation_log_id: invocation_log_id}
        } = conn,
        _params
      ) do
    case Bazel.get_invocation_log(project.id, invocation_id, invocation_log_id) do
      {:ok, log} ->
        json(conn, invocation_log_json(log))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bazel invocation log not found."})
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
          ],
          operation: [
            in: :query,
            type: %Schema{type: :string, enum: ["action_cache", "cas"]},
            description: "Filter by action cache or content-addressable storage operation."
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
      |> maybe_append_filter(:operation, params[:operation])

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
      target_patterns: invocation.target_patterns,
      git_branch: invocation.git_branch,
      git_commit_sha: invocation.git_commit_sha,
      is_ci: invocation.is_ci,
      bazel_version: invocation.bazel_version,
      cache_endpoint: invocation.cache_endpoint,
      status: invocation.status,
      exit_code: invocation.exit_code,
      started_at: invocation.started_at,
      finished_at: invocation.finished_at,
      duration_ms: invocation.duration_ms,
      build_metrics: build_metrics_json(invocation),
      build_timeline: build_timeline_json(invocation),
      critical_path: critical_path_json(invocation),
      cache: invocation.cache
    }
  end

  defp invocation_log_json(log) do
    %{
      id: log.id,
      invocation_id: log.invocation_id,
      sequence_number: log.sequence_number,
      stream: log.stream,
      message: log.message,
      observed_at: log.observed_at
    }
  end

  defp build_metrics_json(invocation) do
    %{
      cpu_time_ms: invocation.cpu_time_ms,
      actions_created: invocation.actions_created,
      actions_executed: invocation.actions_executed,
      targets_configured: invocation.targets_configured,
      packages_loaded: invocation.packages_loaded
    }
  end

  defp build_timeline_json(invocation) do
    spans =
      [
        invocation.build_timeline_span_lanes,
        invocation.build_timeline_span_start_ms,
        invocation.build_timeline_span_durations_ms,
        invocation.build_timeline_span_categories,
        invocation.build_timeline_span_descriptions
      ]
      |> Enum.zip()
      |> Enum.map(fn {lane, start_ms, duration_ms, category, description} ->
        %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description}
      end)

    if spans == [] do
      nil
    else
      %{duration_ms: invocation.build_timeline_duration_ms, lanes: invocation.build_timeline_lanes, spans: spans}
    end
  end

  defp critical_path_json(invocation) do
    actions =
      invocation.critical_path_action_descriptions
      |> Enum.zip(invocation.critical_path_action_durations_ms)
      |> Enum.map(fn {description, duration_ms} -> %{description: description, duration_ms: duration_ms} end)

    if invocation.critical_path_duration_ms == 0 and actions == [] do
      nil
    else
      %{duration_ms: invocation.critical_path_duration_ms, actions: actions}
    end
  end

  defp cache_event_json(event) do
    %{
      id: event.id,
      invocation_id: event.invocation_id,
      client_kind: event.client_kind,
      operation: event.operation,
      outcome: event.outcome,
      action_digest: event.action_digest,
      action_mnemonic: event.action_mnemonic,
      target_label: event.target_label,
      configuration_id: event.configuration_id,
      size: event.size,
      duration_ms: event.duration_ms,
      cache_endpoint: event.cache_endpoint,
      observed_at: event.observed_at,
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
