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
  @critical_path_action_schema %Schema{
    type: :object,
    properties: %{
      description: %Schema{type: :string, minLength: 1, maxLength: 512},
      duration_ms: %Schema{type: :integer, minimum: 0}
    },
    required: [:description, :duration_ms]
  }
  @critical_path_schema %Schema{
    type: :object,
    properties: %{
      duration_ms: %Schema{type: :integer, minimum: 0},
      actions: %Schema{type: :array, maxItems: 25, items: @critical_path_action_schema}
    },
    required: [:duration_ms, :actions]
  }
  @build_timeline_span_schema %Schema{
    type: :object,
    properties: %{
      lane: %Schema{type: :integer, minimum: 0, maximum: 7},
      start_ms: %Schema{type: :integer, minimum: 0},
      duration_ms: %Schema{type: :integer, minimum: 1},
      category: %Schema{type: :string, enum: ["analysis", "critical_path", "execution", "loading", "setup", "other"]},
      description: %Schema{type: :string, minLength: 1, maxLength: 512}
    },
    required: [:lane, :start_ms, :duration_ms, :category, :description]
  }
  @build_timeline_schema %Schema{
    type: :object,
    properties: %{
      duration_ms: %Schema{type: :integer, minimum: 1},
      lanes: %Schema{type: :array, minItems: 1, maxItems: 8, items: %Schema{type: :string, maxLength: 32}},
      spans: %Schema{type: :array, minItems: 1, maxItems: 180, items: @build_timeline_span_schema}
    },
    required: [:duration_ms, :lanes, :spans]
  }
  @build_metrics_schema %Schema{
    type: :object,
    properties: %{
      cpu_time_ms: %Schema{type: :integer, minimum: 0},
      actions_executed: %Schema{type: :integer, minimum: 0},
      targets_loaded: %Schema{type: :integer, minimum: 0},
      targets_configured: %Schema{type: :integer, minimum: 0},
      packages_loaded: %Schema{type: :integer, minimum: 0}
    },
    required: [:cpu_time_ms, :actions_executed, :targets_loaded, :targets_configured, :packages_loaded]
  }
  @invocation_schema %Schema{
    type: :object,
    properties: %{
      invocation_id: %Schema{type: :string},
      command: %Schema{type: :string},
      target_patterns: %Schema{type: :array, items: %Schema{type: :string}},
      requested_command: %Schema{type: :string},
      original_command_line: %Schema{type: :array, items: %Schema{type: :string}},
      canonical_command_line: %Schema{type: :array, items: %Schema{type: :string}},
      bazel_version: %Schema{type: :string},
      client_platform: %Schema{type: :string},
      git_branch: %Schema{type: :string},
      git_commit_sha: %Schema{type: :string},
      configurations: %Schema{type: :array, items: %Schema{type: :string}},
      compilation_mode: %Schema{type: :string, enum: ["", "dbg", "fastbuild", "opt"]},
      remote_cache_enabled: %Schema{type: :boolean},
      remote_execution_enabled: %Schema{type: :boolean},
      status: %Schema{type: :string, enum: ["success", "failure"]},
      exit_code: %Schema{type: :integer},
      started_at: %Schema{type: :string, format: :"date-time"},
      finished_at: %Schema{type: :string, format: :"date-time"},
      duration_ms: %Schema{type: :integer},
      build_metrics: @build_metrics_schema,
      build_timeline: %Schema{
        type: :object,
        nullable: true,
        properties: @build_timeline_schema.properties,
        required: @build_timeline_schema.required
      },
      critical_path: %Schema{
        type: :object,
        nullable: true,
        properties: @critical_path_schema.properties,
        required: @critical_path_schema.required
      },
      cache: @cache_summary_schema
    },
    required: [
      :invocation_id,
      :command,
      :target_patterns,
      :bazel_version,
      :client_platform,
      :git_branch,
      :git_commit_sha,
      :configurations,
      :compilation_mode,
      :remote_cache_enabled,
      :remote_execution_enabled,
      :status,
      :exit_code,
      :started_at,
      :finished_at,
      :duration_ms,
      :build_metrics,
      :cache
    ]
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
  @test_result_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      invocation_id: %Schema{type: :string},
      target_label: %Schema{type: :string},
      status: %Schema{type: :string, enum: ["success", "failure", "flaky", "skipped"]},
      duration_ms: %Schema{type: :integer},
      attempt_count: %Schema{type: :integer},
      finished_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :invocation_id, :target_label, :status, :duration_ms, :attempt_count, :finished_at]
  }
  @invocation_submission_schema %Schema{
    type: :object,
    properties: %{
      invocation_id: %Schema{type: :string, minLength: 1, maxLength: 255},
      command: %Schema{type: :string, minLength: 1, maxLength: 128},
      requested_command: %Schema{type: :string, maxLength: 16_384},
      original_command_line: %Schema{type: :array, maxItems: 500, items: %Schema{type: :string, maxLength: 2_048}},
      canonical_command_line: %Schema{type: :array, maxItems: 500, items: %Schema{type: :string, maxLength: 2_048}},
      status: %Schema{type: :string, enum: ["success", "failure"]},
      exit_code: %Schema{type: :integer},
      started_at: %Schema{type: :string, format: :"date-time"},
      finished_at: %Schema{type: :string, format: :"date-time"},
      target_patterns: %Schema{type: :array, items: %Schema{type: :string}, maxItems: 100},
      bazel_version: %Schema{type: :string, maxLength: 128},
      client_platform: %Schema{type: :string, maxLength: 32},
      git_branch: %Schema{type: :string, maxLength: 255, nullable: true},
      git_commit_sha: %Schema{type: :string, maxLength: 64, nullable: true},
      configurations: %Schema{type: :array, items: %Schema{type: :string}, maxItems: 20},
      compilation_mode: %Schema{type: :string, enum: ["", "dbg", "fastbuild", "opt"]},
      remote_cache_enabled: %Schema{type: :boolean},
      remote_execution_enabled: %Schema{type: :boolean},
      build_metrics: @build_metrics_schema,
      build_timeline: @build_timeline_schema,
      critical_path: @critical_path_schema
    },
    required: [
      :invocation_id,
      :command,
      :status,
      :exit_code,
      :started_at,
      :finished_at,
      :target_patterns,
      :bazel_version,
      :configurations,
      :compilation_mode,
      :remote_cache_enabled,
      :remote_execution_enabled
    ]
  }

  @omitted_command_line_options MapSet.new(["client_env"])
  @redacted_command_line_option_fragments [
    "auth",
    "bazelrc",
    "binary_path",
    "build_event",
    "client_cwd",
    "cookie",
    "credential",
    "failure_detail",
    "header",
    "host_jvm_args",
    "install_base",
    "install_md5",
    "key",
    "output_base",
    "output_user_root",
    "password",
    "private",
    "profile",
    "proxy",
    "rc_source",
    "repo_env",
    "repository_cache",
    "sandbox_base",
    "secret",
    "token",
    "workspace_directory"
  ]
  @command_option_pattern ~r/(^|\s)--([A-Za-z0-9_-]+)(?:=('[^']*'|"[^"]*"|[^[:space:]]+)|\s+('[^']*'|"[^"]*"|[^[:space:]]+))/
  @test_results_submission_schema %Schema{
    type: :object,
    properties: %{
      test_results: %Schema{
        type: :array,
        maxItems: 1_000,
        items: %Schema{
          type: :object,
          properties: %{
            invocation_id: %Schema{type: :string, minLength: 1, maxLength: 255},
            target_label: %Schema{type: :string, minLength: 1, maxLength: 1_024},
            status: %Schema{type: :string, enum: ["success", "failure", "flaky", "skipped"]},
            duration_ms: %Schema{type: :integer, minimum: 0},
            attempt_count: %Schema{type: :integer, minimum: 1},
            finished_at: %Schema{type: :string, format: :"date-time"}
          },
          required: [:invocation_id, :target_label, :status, :duration_ms, :attempt_count, :finished_at]
        }
      }
    },
    required: [:test_results]
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

  operation(:create_invocation,
    summary: "Record a completed Bazel invocation sent directly by the Tuist client.",
    operation_id: "createBazelInvocation",
    parameters: @project_parameters,
    request_body: {"Completed Bazel invocation", "application/json", @invocation_submission_schema},
    responses: %{
      accepted: {"Bazel invocation accepted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid request", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def create_invocation(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    case invocation_from_submission(body, project) do
      {:ok, invocation} ->
        Bazel.create_invocations([invocation])

        conn
        |> put_status(:accepted)
        |> json(%{})

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid Bazel invocation."})
    end
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

  operation(:list_test_results,
    summary: "List Bazel test-target results for a project.",
    operation_id: "listBazelTestResults",
    parameters:
      @project_parameters ++
        @pagination_parameters ++
        [
          status: [
            in: :query,
            type: %Schema{type: :string, enum: ["success", "failure", "flaky", "skipped"]},
            description: "Filter by test-target status."
          ],
          invocation_id: [in: :query, type: :string, description: "Filter by Bazel invocation identifier."]
        ],
    responses: %{
      ok:
        {"List of Bazel test-target results", "application/json",
         %Schema{
           type: :object,
           properties: %{
             test_results: %Schema{type: :array, items: @test_result_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:test_results, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def list_test_results(
        %{assigns: %{selected_project: project}, params: %{page: page, page_size: page_size} = params} = conn,
        _params
      ) do
    filters =
      [%{field: :project_id, op: :==, value: project.id}]
      |> maybe_append_filter(:status, params[:status])
      |> maybe_append_filter(:invocation_id, params[:invocation_id])

    {test_results, meta} =
      Bazel.list_test_results(project.id, %{
        filters: filters,
        order_by: [:finished_at],
        order_directions: [:desc],
        page: page,
        page_size: page_size
      })

    json(conn, %{test_results: Enum.map(test_results, &test_result_json/1), pagination_metadata: pagination_json(meta)})
  end

  operation(:create_test_results,
    summary: "Record final Bazel test-target results sent directly by the Tuist client.",
    operation_id: "createBazelTestResults",
    parameters: @project_parameters,
    request_body: {"Final Bazel test-target results", "application/json", @test_results_submission_schema},
    responses: %{
      accepted: {"Bazel test-target results accepted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid request", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def create_test_results(
        %{assigns: %{selected_project: project}, body_params: %{test_results: test_results}} = conn,
        _params
      ) do
    case test_results_from_submission(test_results, project) do
      {:ok, test_results} ->
        Bazel.create_test_results(test_results)

        conn
        |> put_status(:accepted)
        |> json(%{})

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid Bazel test results."})
    end
  end

  operation(:get_test_result,
    summary: "Get a Bazel test-target result by its identifier.",
    operation_id: "getBazelTestResult",
    parameters:
      @project_parameters ++
        [
          test_result_id: [
            in: :path,
            type: :string,
            required: true,
            description: "The Bazel test-target result identifier."
          ]
        ],
    responses: %{
      ok: {"Bazel test-target result", "application/json", @test_result_schema},
      not_found: {"Bazel test-target result not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def get_test_result(%{assigns: %{selected_project: project}, params: %{test_result_id: test_result_id}} = conn, _params) do
    case Bazel.get_test_result(project.id, test_result_id) do
      {:ok, test_result} ->
        json(conn, test_result_json(test_result))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Bazel test result not found."})
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
      target_patterns: invocation.target_patterns,
      requested_command: invocation.requested_command,
      original_command_line: invocation.original_command_line,
      canonical_command_line: invocation.canonical_command_line,
      bazel_version: invocation.bazel_version,
      client_platform: invocation.client_platform,
      git_branch: invocation.git_branch,
      git_commit_sha: invocation.git_commit_sha,
      configurations: invocation.configurations,
      compilation_mode: invocation.compilation_mode,
      remote_cache_enabled: invocation.remote_cache_enabled,
      remote_execution_enabled: invocation.remote_execution_enabled,
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

  defp invocation_from_submission(body, project) do
    git_branch = Map.get(body, :git_branch)
    git_commit_sha = Map.get(body, :git_commit_sha)
    client_platform = Map.get(body, :client_platform, "unknown")

    with true <- valid_command?(body.command),
         true <- valid_configurations?(body.configurations),
         true <- valid_target_patterns?(body.target_patterns),
         true <- valid_requested_command?(Map.get(body, :requested_command)),
         true <- valid_command_line?(Map.get(body, :original_command_line)),
         true <- valid_command_line?(Map.get(body, :canonical_command_line)),
         true <- valid_git_branch?(git_branch),
         true <- valid_git_commit_sha?(git_commit_sha),
         true <- valid_client_platform?(client_platform),
         true <- DateTime.compare(body.finished_at, body.started_at) != :lt,
         {:ok, build_metrics} <- build_metrics_from_submission(Map.get(body, :build_metrics)),
         {:ok, build_timeline} <- build_timeline_from_submission(Map.get(body, :build_timeline)),
         {:ok, critical_path} <- critical_path_from_submission(Map.get(body, :critical_path)) do
      {:ok,
       %{
         invocation_id: body.invocation_id,
         command: body.command,
         status: body.status,
         exit_code: body.exit_code,
         started_at: body.started_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
         finished_at: body.finished_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
         duration_ms: DateTime.diff(body.finished_at, body.started_at, :millisecond),
         target_patterns: body.target_patterns,
         requested_command: sanitized_requested_command(Map.get(body, :requested_command)),
         original_command_line: sanitized_command_line(Map.get(body, :original_command_line)),
         canonical_command_line: sanitized_command_line(Map.get(body, :canonical_command_line)),
         bazel_version: body.bazel_version,
         client_platform: client_platform,
         git_branch: normalized_git_branch(git_branch),
         git_commit_sha: normalized_git_commit_sha(git_commit_sha),
         configurations: body.configurations,
         compilation_mode: body.compilation_mode,
         remote_cache_enabled: body.remote_cache_enabled,
         remote_execution_enabled: body.remote_execution_enabled,
         cpu_time_ms: build_metrics.cpu_time_ms,
         actions_executed: build_metrics.actions_executed,
         targets_loaded: build_metrics.targets_loaded,
         targets_configured: build_metrics.targets_configured,
         packages_loaded: build_metrics.packages_loaded,
         build_timeline_duration_ms: build_timeline.duration_ms,
         build_timeline_lanes: build_timeline.lanes,
         build_timeline_span_lanes: build_timeline.span_lanes,
         build_timeline_span_start_ms: build_timeline.span_start_ms,
         build_timeline_span_durations_ms: build_timeline.span_durations_ms,
         build_timeline_span_categories: build_timeline.span_categories,
         build_timeline_span_descriptions: build_timeline.span_descriptions,
         critical_path_duration_ms: critical_path.duration_ms,
         critical_path_action_descriptions: critical_path.action_descriptions,
         critical_path_action_durations_ms: critical_path.action_durations_ms,
         project_id: project.id,
         account_handle: project.account.name,
         project_handle: project.name,
         cache_endpoint: ""
       }}
    else
      _ -> :error
    end
  end

  defp test_results_from_submission(test_results, project) when is_list(test_results) do
    test_results
    |> Enum.reduce_while({:ok, []}, fn test_result, {:ok, entries} ->
      if valid_target_label?(test_result.target_label) do
        entry = %{
          invocation_id: test_result.invocation_id,
          target_label: test_result.target_label,
          status: test_result.status,
          duration_ms: test_result.duration_ms,
          attempt_count: test_result.attempt_count,
          finished_at: test_result.finished_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
          project_id: project.id,
          account_handle: project.account.name,
          project_handle: project.name,
          cache_endpoint: ""
        }

        {:cont, {:ok, [entry | entries]}}
      else
        {:halt, :error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      :error -> :error
    end
  end

  defp test_results_from_submission(_, _), do: :error

  defp valid_command?(command), do: is_binary(command) and String.length(String.trim(command)) in 1..128

  defp valid_requested_command?(nil), do: true

  defp valid_requested_command?(command) do
    is_binary(command) and String.length(command) <= 16_384 and String.printable?(command)
  end

  defp valid_command_line?(nil), do: true

  defp valid_command_line?(command_line) do
    is_list(command_line) and length(command_line) <= 500 and
      Enum.all?(command_line, fn option ->
        is_binary(option) and String.length(option) in 1..2_048 and String.printable?(option)
      end)
  end

  defp sanitized_requested_command(command) when is_binary(command) do
    @command_option_pattern
    |> Regex.replace(command, fn match, prefix, option, _equals_value, _space_value ->
      option = String.downcase(option)

      cond do
        MapSet.member?(@omitted_command_line_options, option) -> prefix
        redact_command_line_option?(option) -> "#{prefix}--#{option}=<REDACTED>"
        true -> match
      end
    end)
    |> String.trim()
  end

  defp sanitized_requested_command(_), do: ""

  defp sanitized_command_line(command_line) when is_list(command_line) do
    command_line
    |> Enum.map(&sanitized_command_line_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp sanitized_command_line(_), do: []

  defp sanitized_command_line_option(option) do
    case Regex.run(~r/^--([A-Za-z0-9_-]+)/, option) do
      [_, option_name] ->
        option_name = String.downcase(option_name)

        cond do
          MapSet.member?(@omitted_command_line_options, option_name) -> nil
          redact_command_line_option?(option_name) -> "--#{option_name}=<REDACTED>"
          true -> option
        end

      _ ->
        option
    end
  end

  defp redact_command_line_option?(option_name) do
    Enum.any?(@redacted_command_line_option_fragments, &String.contains?(option_name, &1))
  end

  defp valid_target_patterns?(target_patterns) do
    is_list(target_patterns) and
      Enum.all?(target_patterns, &(is_binary(&1) and String.length(String.trim(&1)) in 1..1_024))
  end

  defp valid_configurations?(configurations) do
    is_list(configurations) and
      Enum.all?(configurations, fn configuration ->
        is_binary(configuration) and String.match?(configuration, ~r/^[A-Za-z0-9_.\/-]{1,128}$/)
      end)
  end

  defp valid_git_branch?(nil), do: true
  defp valid_git_branch?(""), do: true

  defp valid_git_branch?(git_branch) when is_binary(git_branch) do
    String.match?(git_branch, ~r/^[A-Za-z0-9][A-Za-z0-9._\/-]{0,254}$/) and
      not String.contains?(git_branch, "..") and not String.contains?(git_branch, "//")
  end

  defp valid_git_branch?(_), do: false

  defp valid_git_commit_sha?(nil), do: true
  defp valid_git_commit_sha?(""), do: true

  defp valid_git_commit_sha?(git_commit_sha) when is_binary(git_commit_sha),
    do: String.match?(git_commit_sha, ~r/^[A-Fa-f0-9]{7,64}$/)

  defp valid_git_commit_sha?(_), do: false

  defp normalized_git_branch(nil), do: ""
  defp normalized_git_branch(git_branch), do: git_branch

  defp normalized_git_commit_sha(nil), do: ""
  defp normalized_git_commit_sha(git_commit_sha), do: git_commit_sha

  defp valid_client_platform?(platform)
       when platform in ["unknown", "macos_arm64", "macos_x86_64", "linux_arm64", "linux_x86_64"], do: true

  defp valid_client_platform?(_), do: false

  defp build_metrics_from_submission(nil), do: {:ok, empty_build_metrics()}

  defp build_metrics_from_submission(metrics) when is_map(metrics) do
    with cpu_time_ms when is_integer(cpu_time_ms) and cpu_time_ms >= 0 <- Map.get(metrics, :cpu_time_ms, 0),
         actions_executed when is_integer(actions_executed) and actions_executed >= 0 <-
           Map.get(metrics, :actions_executed, 0),
         targets_loaded when is_integer(targets_loaded) and targets_loaded >= 0 <- Map.get(metrics, :targets_loaded, 0),
         targets_configured when is_integer(targets_configured) and targets_configured >= 0 <-
           Map.get(metrics, :targets_configured, 0),
         packages_loaded when is_integer(packages_loaded) and packages_loaded >= 0 <-
           Map.get(metrics, :packages_loaded, 0) do
      {:ok,
       %{
         cpu_time_ms: cpu_time_ms,
         actions_executed: actions_executed,
         targets_loaded: targets_loaded,
         targets_configured: targets_configured,
         packages_loaded: packages_loaded
       }}
    else
      _ -> :error
    end
  end

  defp build_metrics_from_submission(_), do: :error

  defp empty_build_metrics do
    %{cpu_time_ms: 0, actions_executed: 0, targets_loaded: 0, targets_configured: 0, packages_loaded: 0}
  end

  defp build_metrics_json(invocation) do
    %{
      cpu_time_ms: invocation.cpu_time_ms,
      actions_executed: invocation.actions_executed,
      targets_loaded: invocation.targets_loaded,
      targets_configured: invocation.targets_configured,
      packages_loaded: invocation.packages_loaded
    }
  end

  defp build_timeline_from_submission(nil), do: {:ok, empty_build_timeline()}

  defp build_timeline_from_submission(%{duration_ms: duration_ms, lanes: lanes, spans: spans})
       when is_integer(duration_ms) and duration_ms > 0 and is_list(lanes) and is_list(spans) and length(lanes) in 1..8 and
              length(spans) in 1..180 do
    if Enum.all?(lanes, &valid_timeline_lane?/1) and Enum.all?(spans, &valid_timeline_span?(&1, lanes, duration_ms)) do
      {:ok,
       %{
         duration_ms: duration_ms,
         lanes: lanes,
         span_lanes: Enum.map(spans, & &1.lane),
         span_start_ms: Enum.map(spans, & &1.start_ms),
         span_durations_ms: Enum.map(spans, & &1.duration_ms),
         span_categories: Enum.map(spans, & &1.category),
         span_descriptions: Enum.map(spans, & &1.description)
       }}
    else
      :error
    end
  end

  defp build_timeline_from_submission(_), do: :error

  defp empty_build_timeline do
    %{
      duration_ms: 0,
      lanes: [],
      span_lanes: [],
      span_start_ms: [],
      span_durations_ms: [],
      span_categories: [],
      span_descriptions: []
    }
  end

  defp valid_timeline_lane?("Critical path"), do: true

  defp valid_timeline_lane?("Worker " <> worker_number) do
    case Integer.parse(worker_number) do
      {number, ""} when number in 1..8 -> true
      _ -> false
    end
  end

  defp valid_timeline_lane?(_), do: false

  defp valid_timeline_span?(
         %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description},
         lanes,
         timeline_duration_ms
       ) do
    is_integer(lane) and lane in 0..(length(lanes) - 1) and
      is_integer(start_ms) and start_ms >= 0 and
      is_integer(duration_ms) and duration_ms > 0 and
      start_ms + duration_ms <= timeline_duration_ms and
      category in ["analysis", "critical_path", "execution", "loading", "setup", "other"] and
      is_binary(description) and String.length(String.trim(description)) in 1..512 and String.printable?(description) and
      not String.match?(description, ~r/(^|[\s'\"])(?:\/(?!\/)|~\/|[A-Za-z]:\\)/)
  end

  defp valid_timeline_span?(_, _, _), do: false

  defp build_timeline_json(invocation) do
    spans =
      [
        Map.get(invocation, :build_timeline_span_lanes, []),
        Map.get(invocation, :build_timeline_span_start_ms, []),
        Map.get(invocation, :build_timeline_span_durations_ms, []),
        Map.get(invocation, :build_timeline_span_categories, []),
        Map.get(invocation, :build_timeline_span_descriptions, [])
      ]
      |> Enum.zip()
      |> Enum.map(fn {lane, start_ms, duration_ms, category, description} ->
        %{lane: lane, start_ms: start_ms, duration_ms: duration_ms, category: category, description: description}
      end)

    case spans do
      [] ->
        nil

      spans ->
        %{
          duration_ms: Map.get(invocation, :build_timeline_duration_ms, 0),
          lanes: Map.get(invocation, :build_timeline_lanes, []),
          spans: spans
        }
    end
  end

  defp valid_target_label?(target_label),
    do: is_binary(target_label) and String.length(String.trim(target_label)) in 1..1_024

  defp critical_path_from_submission(nil), do: {:ok, empty_critical_path()}

  defp critical_path_from_submission(%{duration_ms: duration_ms, actions: actions})
       when is_integer(duration_ms) and duration_ms >= 0 and is_list(actions) and length(actions) in 1..25 do
    if Enum.all?(actions, &valid_critical_path_action?/1) do
      {:ok,
       %{
         duration_ms: duration_ms,
         action_descriptions: Enum.map(actions, & &1.description),
         action_durations_ms: Enum.map(actions, & &1.duration_ms)
       }}
    else
      :error
    end
  end

  defp critical_path_from_submission(_), do: :error

  defp empty_critical_path do
    %{duration_ms: 0, action_descriptions: [], action_durations_ms: []}
  end

  defp valid_critical_path_action?(%{description: description, duration_ms: duration_ms}) do
    is_integer(duration_ms) and duration_ms >= 0 and
      is_binary(description) and
      String.length(String.trim(description)) in 1..512 and
      String.printable?(description) and
      not String.starts_with?(String.trim_leading(description), "/")
  end

  defp valid_critical_path_action?(_), do: false

  defp critical_path_json(invocation) do
    actions =
      invocation
      |> Map.get(:critical_path_action_descriptions, [])
      |> Enum.zip(Map.get(invocation, :critical_path_action_durations_ms, []))
      |> Enum.map(fn {description, duration_ms} -> %{description: description, duration_ms: duration_ms} end)

    case actions do
      [] -> nil
      actions -> %{duration_ms: Map.get(invocation, :critical_path_duration_ms, 0), actions: actions}
    end
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

  defp test_result_json(test_result) do
    %{
      id: test_result.id,
      invocation_id: test_result.invocation_id,
      target_label: test_result.target_label,
      status: test_result.status,
      duration_ms: test_result.duration_ms,
      attempt_count: test_result.attempt_count,
      finished_at: test_result.finished_at
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
