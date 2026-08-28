defmodule TuistWeb.API.RunnersController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.FeatureFlags
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias Tuist.Runners.Profiles
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)

  # Profiles live on the account settings surface, where the dashboard
  # requires account administrators even for the read-only table. The
  # operational runner views intentionally remain visible to runner readers.
  plug AuthorizationPlug, {:account, :account, :update} when action in [:index_profiles]

  plug AuthorizationPlug,
       {:account, :runners}
       when action in [:index_jobs, :show_job, :index_job_steps, :index_job_metrics, :index_job_logs, :index_workflows]

  tags ["Runners"]

  @runner_job_schema %Schema{
    title: "RunnerJob",
    type: :object,
    properties: %{
      workflow_job_id: %Schema{type: :integer},
      repository: %Schema{type: :string},
      workflow_run_id: %Schema{type: :integer},
      workflow_name: %Schema{type: :string},
      run_attempt: %Schema{type: :integer},
      job_name: %Schema{type: :string},
      head_branch: %Schema{type: :string},
      head_sha: %Schema{type: :string},
      status: %Schema{type: :string},
      conclusion: %Schema{type: :string},
      platform: %Schema{type: :string},
      vcpus: %Schema{type: :integer},
      memory_gb: %Schema{type: :integer},
      requested_dispatch_label: %Schema{type: :string},
      enqueued_at: %Schema{type: :string, format: "date-time"},
      claimed_at: %Schema{type: :string, format: "date-time", nullable: true},
      started_at: %Schema{type: :string, format: "date-time", nullable: true},
      completed_at: %Schema{type: :string, format: "date-time", nullable: true},
      log_archived_at: %Schema{type: :string, format: "date-time", nullable: true},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :workflow_job_id,
      :repository,
      :workflow_run_id,
      :workflow_name,
      :run_attempt,
      :job_name,
      :head_branch,
      :head_sha,
      :status,
      :conclusion,
      :platform,
      :vcpus,
      :memory_gb,
      :requested_dispatch_label,
      :enqueued_at,
      :updated_at
    ]
  }

  @workflow_schema %Schema{
    title: "RunnerWorkflow",
    type: :object,
    properties: %{
      workflow_name: %Schema{type: :string},
      repository: %Schema{type: :string},
      total_jobs: %Schema{type: :integer},
      success_count: %Schema{type: :integer},
      failure_count: %Schema{type: :integer},
      cancelled_count: %Schema{type: :integer},
      skipped_count: %Schema{type: :integer},
      in_progress_count: %Schema{type: :integer},
      avg_duration_ms: %Schema{type: :number, nullable: true},
      last_run_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :workflow_name,
      :repository,
      :total_jobs,
      :success_count,
      :failure_count,
      :cancelled_count,
      :skipped_count,
      :in_progress_count,
      :last_run_at
    ]
  }

  @profile_schema %Schema{
    title: "RunnerProfile",
    type: :object,
    properties: %{
      id: %Schema{type: :integer},
      name: %Schema{type: :string},
      platform: %Schema{type: :string, enum: ["linux", "macos"]},
      vcpus: %Schema{type: :integer},
      memory_gb: %Schema{type: :integer},
      xcode_version: %Schema{type: :string, nullable: true},
      protected: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [:id, :name, :platform, :vcpus, :memory_gb, :protected, :inserted_at, :updated_at]
  }

  @job_step_schema %Schema{
    title: "RunnerJobStep",
    type: :object,
    properties: %{
      number: %Schema{type: :integer},
      name: %Schema{type: :string},
      status: %Schema{type: :string},
      conclusion: %Schema{type: :string},
      started_at: %Schema{type: :string, format: "date-time", nullable: true},
      completed_at: %Schema{type: :string, format: "date-time", nullable: true}
    },
    required: [:number, :name, :status, :conclusion, :started_at, :completed_at]
  }

  @job_metric_schema %Schema{
    title: "RunnerJobMetric",
    type: :object,
    properties: %{
      timestamp: %Schema{type: :number},
      cpu_usage_percent: %Schema{type: :number},
      cpu_iowait_percent: %Schema{type: :number},
      memory_used_bytes: %Schema{type: :integer},
      memory_total_bytes: %Schema{type: :integer},
      network_bytes_in: %Schema{type: :integer},
      network_bytes_out: %Schema{type: :integer},
      disk_used_bytes: %Schema{type: :integer},
      disk_total_bytes: %Schema{type: :integer}
    },
    required: [
      :timestamp,
      :cpu_usage_percent,
      :cpu_iowait_percent,
      :memory_used_bytes,
      :memory_total_bytes,
      :network_bytes_in,
      :network_bytes_out,
      :disk_used_bytes,
      :disk_total_bytes
    ]
  }

  @job_log_schema %Schema{
    title: "RunnerJobLogLine",
    type: :object,
    properties: %{
      line_number: %Schema{type: :integer},
      ts: %Schema{type: :string, format: "date-time", nullable: true},
      message: %Schema{type: :string}
    },
    required: [:line_number, :ts, :message]
  }

  @account_parameters [
    account_handle: [
      in: :path,
      type: :string,
      required: true,
      description: "The account handle."
    ]
  ]

  @pagination_parameters [
    page: [in: :query, type: :integer, required: false, description: "Page number (default: 1)."],
    page_size: [in: :query, type: :integer, required: false, description: "Results per page (default: 20, maximum: 100)."]
  ]

  @job_filter_parameters @pagination_parameters ++
                           [
                             status: [
                               in: :query,
                               type: %Schema{type: :string, enum: ["queued", "claimed", "running", "completed"]},
                               required: false
                             ],
                             conclusion: [
                               in: :query,
                               type: %Schema{type: :string, enum: ["success", "failure", "cancelled", "skipped"]},
                               required: false
                             ],
                             repository: [in: :query, type: :string, required: false],
                             workflow_name: [in: :query, type: :string, required: false],
                             job_name: [in: :query, type: :string, required: false],
                             head_branch: [in: :query, type: :string, required: false],
                             platform: [
                               in: :query,
                               type: %Schema{type: :string, enum: ["linux", "macos"]},
                               required: false
                             ],
                             search: [in: :query, type: :string, required: false],
                             sort_by: [
                               in: :query,
                               type: %Schema{type: :string, enum: ["enqueued", "job", "workflow", "duration"]},
                               required: false
                             ],
                             sort_order: [
                               in: :query,
                               type: %Schema{type: :string, enum: ["asc", "desc"]},
                               required: false
                             ]
                           ]

  @workflow_filter_parameters @pagination_parameters ++
                                [
                                  repository: [in: :query, type: :string, required: false],
                                  workflow_name: [in: :query, type: :string, required: false],
                                  head_branch: [in: :query, type: :string, required: false],
                                  platform: [
                                    in: :query,
                                    type: %Schema{type: :string, enum: ["linux", "macos"]},
                                    required: false
                                  ],
                                  sort_by: [
                                    in: :query,
                                    type: %Schema{
                                      type: :string,
                                      enum: ["workflow", "success_rate", "jobs", "avg_duration"]
                                    },
                                    required: false
                                  ],
                                  sort_order: [
                                    in: :query,
                                    type: %Schema{type: :string, enum: ["asc", "desc"]},
                                    required: false
                                  ]
                                ]

  operation(:index_jobs,
    summary: "List runner jobs for an account.",
    operation_id: "listRunnerJobs",
    parameters: @account_parameters ++ @job_filter_parameters,
    responses: %{
      ok:
        {"Runner jobs", "application/json",
         %Schema{
           type: :object,
           properties: %{jobs: %Schema{type: :array, items: @runner_job_schema}, pagination_metadata: PaginationMetadata},
           required: [:jobs, :pagination_metadata]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_jobs(%{assigns: %{selected_account: account}} = conn, params) do
    if FeatureFlags.runners_enabled?(account) do
      {page, page_size} = page_params(params)
      options = job_options(params) ++ [limit: page_size, offset: (page - 1) * page_size]
      total_count = Jobs.count_for_account(account.id, job_options(params))
      jobs = Jobs.list_for_account(account.id, options)

      json(conn, %{
        jobs: Enum.map(jobs, &serialize_job/1),
        pagination_metadata: pagination_metadata(page, page_size, total_count)
      })
    else
      runners_unavailable(conn)
    end
  end

  operation(:show_job,
    summary: "Get a runner job.",
    operation_id: "getRunnerJob",
    parameters:
      @account_parameters ++
        [
          workflow_job_id: [
            in: :path,
            type: :integer,
            required: true,
            description: "The workflow job identifier."
          ]
        ],
    responses: %{
      ok: {"Runner job", "application/json", @runner_job_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runner job was not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show_job(%{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn, _params) do
    if FeatureFlags.runners_enabled?(account) do
      case Jobs.get_for_account(account.id, workflow_job_id) do
        {:ok, job} -> json(conn, serialize_job(job))
        {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Runner job not found."})
      end
    else
      runners_unavailable(conn)
    end
  end

  operation(:index_job_steps,
    summary: "List the steps for a runner job.",
    operation_id: "listRunnerJobSteps",
    parameters:
      @account_parameters ++
        [workflow_job_id: [in: :path, type: :integer, required: true, description: "The workflow job identifier."]],
    responses: %{
      ok:
        {"Runner job steps", "application/json",
         %Schema{type: :object, properties: %{steps: %Schema{type: :array, items: @job_step_schema}}, required: [:steps]}},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runner job was not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_job_steps(
        %{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn,
        _params
      ) do
    with_runner_job(conn, account, workflow_job_id, fn job ->
      json(conn, %{steps: JobSteps.list_for_job(job.workflow_job_id)})
    end)
  end

  operation(:index_job_metrics,
    summary: "List machine metrics for a runner job.",
    operation_id: "listRunnerJobMetrics",
    parameters:
      @account_parameters ++
        [workflow_job_id: [in: :path, type: :integer, required: true, description: "The workflow job identifier."]],
    responses: %{
      ok:
        {"Runner job metrics", "application/json",
         %Schema{
           type: :object,
           properties: %{metrics: %Schema{type: :array, items: @job_metric_schema}},
           required: [:metrics]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runner job was not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_job_metrics(
        %{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn,
        _params
      ) do
    with_runner_job(conn, account, workflow_job_id, fn job ->
      json(conn, %{metrics: JobMetrics.list_for_job(job.workflow_job_id)})
    end)
  end

  operation(:index_job_logs,
    summary: "List captured log lines for a runner job.",
    description: "Returns log lines in display order. Page size defaults to 200 and is capped at 500.",
    operation_id: "listRunnerJobLogs",
    parameters:
      @account_parameters ++
        [
          workflow_job_id: [in: :path, type: :integer, required: true, description: "The workflow job identifier."],
          offset: [in: :query, type: :integer, required: false, description: "Zero-based log-line offset."],
          limit: [in: :query, type: :integer, required: false, description: "Maximum number of lines, up to 500."]
        ],
    responses: %{
      ok:
        {"Runner job log lines", "application/json",
         %Schema{
           type: :object,
           properties: %{lines: %Schema{type: :array, items: @job_log_schema}},
           required: [:lines]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runner job was not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_job_logs(%{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn, params) do
    with_runner_job(conn, account, workflow_job_id, fn job ->
      limit = params |> Map.get(:limit, 200) |> max(1) |> min(500)
      offset = params |> Map.get(:offset, 0) |> max(0)
      json(conn, %{lines: JobLogs.list_for_job(job.workflow_job_id, limit: limit, offset: offset)})
    end)
  end

  operation(:index_workflows,
    summary: "List runner workflows for an account.",
    operation_id: "listRunnerWorkflows",
    parameters: @account_parameters ++ @workflow_filter_parameters,
    responses: %{
      ok:
        {"Runner workflows", "application/json",
         %Schema{
           type: :object,
           properties: %{
             workflows: %Schema{type: :array, items: @workflow_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:workflows, :pagination_metadata]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_workflows(%{assigns: %{selected_account: account}} = conn, params) do
    if FeatureFlags.runners_enabled?(account) do
      {page, page_size} = page_params(params)
      options = workflow_options(params) ++ [limit: page_size, offset: (page - 1) * page_size]
      total_count = Jobs.count_workflows_for_account(account.id, workflow_options(params))
      workflows = Jobs.list_workflows_for_account(account.id, options)

      json(conn, %{
        workflows: Enum.map(workflows, &serialize_workflow/1),
        pagination_metadata: pagination_metadata(page, page_size, total_count)
      })
    else
      runners_unavailable(conn)
    end
  end

  operation(:index_profiles,
    summary: "List runner profiles for an account.",
    operation_id: "listRunnerProfiles",
    parameters: @account_parameters,
    responses: %{
      ok:
        {"Runner profiles", "application/json",
         %Schema{
           type: :object,
           properties: %{profiles: %Schema{type: :array, items: @profile_schema}},
           required: [:profiles]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_profiles(%{assigns: %{selected_account: account}} = conn, _params) do
    if FeatureFlags.runners_enabled?(account) do
      json(conn, %{profiles: account |> Profiles.list_for_account() |> Enum.map(&serialize_profile/1)})
    else
      runners_unavailable(conn)
    end
  end

  defp page_params(params) do
    page = params |> Map.get(:page, 1) |> max(1)
    page_size = params |> Map.get(:page_size, 20) |> max(1) |> min(100)
    {page, page_size}
  end

  defp job_options(params) do
    Enum.flat_map(
      [
        :status,
        :conclusion,
        :repository,
        :workflow_name,
        :job_name,
        :head_branch,
        :platform,
        :search,
        :sort_by,
        :sort_order
      ],
      fn key -> if value = Map.get(params, key), do: [{key, value}], else: [] end
    )
  end

  defp workflow_options(params) do
    Enum.flat_map([:repository, :workflow_name, :head_branch, :platform, :sort_by, :sort_order], fn key ->
      if value = Map.get(params, key), do: [{key, value}], else: []
    end)
  end

  defp pagination_metadata(page, page_size, total_count) do
    total_pages = ceil(total_count / page_size)

    %{
      has_next_page: page < total_pages,
      has_previous_page: page > 1,
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp serialize_job(job) do
    Map.take(job, [
      :workflow_job_id,
      :repository,
      :workflow_run_id,
      :workflow_name,
      :run_attempt,
      :job_name,
      :head_branch,
      :head_sha,
      :status,
      :conclusion,
      :platform,
      :vcpus,
      :memory_gb,
      :requested_dispatch_label,
      :enqueued_at,
      :claimed_at,
      :started_at,
      :completed_at,
      :log_archived_at,
      :updated_at
    ])
  end

  defp serialize_workflow(workflow),
    do:
      Map.take(workflow, [
        :workflow_name,
        :repository,
        :total_jobs,
        :success_count,
        :failure_count,
        :cancelled_count,
        :skipped_count,
        :in_progress_count,
        :avg_duration_ms,
        :last_run_at
      ])

  defp serialize_profile(profile) do
    Map.take(profile, [:id, :name, :platform, :vcpus, :memory_gb, :xcode_version, :protected, :inserted_at, :updated_at])
  end

  defp with_runner_job(conn, account, workflow_job_id, fun) do
    if FeatureFlags.runners_enabled?(account) do
      case Jobs.get_for_account(account.id, workflow_job_id) do
        {:ok, job} -> fun.(job)
        {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Runner job not found."})
      end
    else
      runners_unavailable(conn)
    end
  end

  defp runners_unavailable(conn),
    do: conn |> put_status(:not_found) |> json(%{message: "Runners are not enabled for this account."})
end
