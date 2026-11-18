defmodule TuistWeb.API.RunnersController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.FeatureFlags
  alias Tuist.Runners.APIJobs
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.JobSteps
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.LoaderPlug)

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug AuthorizationPlug,
       {:account, :runners, :update}
       when action in [:create_profile, :update_profile, :delete_profile, :create_job, :cancel_job]

  plug AuthorizationPlug,
       {:account, :runners}
       when action in [
              :index_jobs,
              :show_job,
              :index_job_steps,
              :index_job_metrics,
              :index_job_logs,
              :index_workflows,
              :index_profiles,
              :catalog
            ]

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

  @runner_job_detail_schema %{
    @runner_job_schema
    | title: "RunnerJobDetail",
      properties:
        Map.put(@runner_job_schema.properties, :out_of_memory, %Schema{
          title: "RunnerJobOutOfMemory",
          type: :object,
          nullable: true,
          description:
            "What the runner VM killed for running out of memory during the job, or null when it killed nothing.",
          properties: %{
            kill_count: %Schema{type: :integer, description: "Processes the runner VM killed."},
            first_kill_at: %Schema{type: :string, format: "date-time", description: "When the first kill was reported."},
            victim: %Schema{
              title: "RunnerJobOutOfMemoryVictim",
              type: :object,
              nullable: true,
              description: "The process killed last, or null when the runner did not name it.",
              properties: %{
                process: %Schema{type: :string},
                memory_bytes: %Schema{type: :integer, description: "Memory the process was using."},
                container: %Schema{
                  type: :string,
                  nullable: true,
                  description: "Its Docker container: null outside a container, docker-build for a docker build step."
                },
                image: %Schema{type: :string, nullable: true, description: "That container's image."}
              },
              required: [:process, :memory_bytes, :container, :image]
            },
            description: %Schema{
              type: :string,
              description: "What happened and what to change, as the job page's \"Ran out of memory\" alert says it."
            }
          },
          required: [:kill_count, :first_kill_at, :victim, :description]
        })
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
      os_version: %Schema{
        type: :string,
        nullable: true,
        description: "The Ubuntu release of a Linux profile, for example ubuntu-24.04. Null on macOS."
      },
      protected: %Schema{type: :boolean},
      runs_on_label: %Schema{
        type: :string,
        description: "The label workflows reference in runs-on to run jobs on this profile."
      },
      cache_writer_all_branches: %Schema{
        type: :boolean,
        description:
          "Whether every successful job from the repository saves custom cache volume changes. When false, only the default branch and the additional branches save."
      },
      cache_writer_default_branch: %Schema{
        type: :boolean,
        description: "Whether jobs on each repository's default branch save custom cache volume changes."
      },
      cache_writer_branches: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Additional branch names or * patterns whose jobs save custom cache volume changes."
      },
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :name,
      :platform,
      :vcpus,
      :memory_gb,
      :protected,
      :runs_on_label,
      :cache_writer_all_branches,
      :cache_writer_default_branch,
      :cache_writer_branches,
      :inserted_at,
      :updated_at
    ]
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
      disk_total_bytes: %Schema{type: :integer},
      oom_kill_count: %Schema{
        type: :integer,
        description: "Processes the runner VM killed for running out of memory since the job started."
      },
      oom_victim_process: %Schema{
        type: :string,
        description: "The process the runner VM killed last for running out of memory, or empty."
      },
      oom_victim_memory_bytes: %Schema{type: :integer, description: "Memory that process was using."},
      oom_victim_container: %Schema{
        type: :string,
        description: "That process's Docker container: empty outside a container, docker-build for a docker build step."
      },
      oom_victim_image: %Schema{type: :string, description: "That container's image, or empty."}
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
      :disk_total_bytes,
      :oom_kill_count,
      :oom_victim_process,
      :oom_victim_memory_bytes,
      :oom_victim_container,
      :oom_victim_image
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

  @profile_name_parameters [
    profile_name: [
      in: :path,
      type: :string,
      required: true,
      description: "The profile name, without the runs-on label prefix."
    ]
  ]

  @profile_change_fields [
    :vcpus,
    :memory_gb,
    :xcode_version,
    :os_version,
    :cache_writer_all_branches,
    :cache_writer_default_branch,
    :cache_writer_branches
  ]

  @profile_change_properties %{
    vcpus: %Schema{type: :integer, description: "vCPUs of an available shape for the platform."},
    memory_gb: %Schema{type: :integer, description: "Memory in GB of an available shape for the platform."},
    xcode_version: %Schema{
      type: :string,
      description: "An available Xcode version, for example 26.5. Required for macOS profiles."
    },
    os_version: %Schema{
      type: :string,
      description:
        "An available Ubuntu release for Linux profiles, for example ubuntu-24.04. Defaults to the catalog default."
    },
    cache_writer_all_branches: %Schema{
      type: :boolean,
      description:
        "Whether every successful job from the repository saves. Defaults to true. When false, only the default branch and the additional branches save."
    },
    cache_writer_default_branch: %Schema{
      type: :boolean,
      description: "Whether jobs on each repository's default branch save. Defaults to true."
    },
    cache_writer_branches: %Schema{
      type: :array,
      items: %Schema{type: :string},
      description: "Additional branch names or * patterns that save. An empty list removes them."
    }
  }

  @catalog_schema %Schema{
    title: "RunnerCatalog",
    type: :object,
    properties: %{
      shapes: %Schema{
        type: :array,
        items: %Schema{
          title: "RunnerShape",
          type: :object,
          properties: %{
            platform: %Schema{type: :string, enum: ["linux", "macos"]},
            vcpus: %Schema{type: :integer},
            memory_gb: %Schema{type: :integer},
            default: %Schema{type: :boolean}
          },
          required: [:platform, :vcpus, :memory_gb, :default]
        }
      },
      xcode_versions: %Schema{
        type: :array,
        items: %Schema{
          title: "RunnerXcodeVersion",
          type: :object,
          properties: %{
            xcode_version: %Schema{type: :string},
            default: %Schema{type: :boolean}
          },
          required: [:xcode_version, :default]
        }
      },
      os_versions: %Schema{
        type: :array,
        items: %Schema{
          title: "RunnerOSVersion",
          type: :object,
          properties: %{
            os_version: %Schema{type: :string},
            label: %Schema{type: :string},
            default: %Schema{type: :boolean}
          },
          required: [:os_version, :label, :default]
        }
      }
    },
    required: [:shapes, :xcode_versions, :os_versions]
  }

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
      ok: {"Runner job", "application/json", @runner_job_detail_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runner job was not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show_job(%{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn, _params) do
    if FeatureFlags.runners_enabled?(account) do
      case Jobs.get_for_account(account.id, workflow_job_id) do
        {:ok, job} ->
          json(conn, Map.put(serialize_job(job), :out_of_memory, JobMetrics.out_of_memory_report(job.workflow_job_id)))

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{message: "Runner job not found."})
      end
    else
      runners_unavailable(conn)
    end
  end

  @variables_schema %Schema{
    type: :object,
    additionalProperties: %Schema{type: :string},
    description:
      "Up to 100 variables. Names are letters, digits and underscores, not starting with a digit or TUIST_RUNNER_; values are up to 32 KiB."
  }

  operation(:create_job,
    summary: "Run a job on a runner profile.",
    description: """
    Queues a job for git forges and orchestrators without a runner protocol of their own. A runner on the profile's pool clones the repository over HTTPS at `commit_sha` and runs `script` with Bash in the checkout. The job fails when the script exits non-zero or runs past `timeout_minutes`.

    Follow the job with `getRunnerJob` and `listRunnerJobLogs`, or subscribe a webhook endpoint to `runner_job.started` and `runner_job.completed`. A request with an `idempotency_key` already used in the account returns that job with 200 instead of creating another one.

    Jobs are untrusted: they get no cache signing grant and no shared cache volumes.
    """,
    operation_id: "createRunnerJob",
    parameters: @account_parameters,
    request_body:
      {"Runner job", "application/json",
       %Schema{
         title: "CreateRunnerJob",
         type: :object,
         properties: %{
           profile: %Schema{type: :string, description: "The profile's name or its runs_on_label."},
           repository_url: %Schema{
             type: :string,
             description: "The repository's HTTPS clone URL, without credentials."
           },
           repository: %Schema{
             type: :string,
             description: "The repository name the dashboard shows. Defaults to the clone URL's path."
           },
           clone_token: %Schema{
             type: :string,
             description:
               "A short-lived credential for cloning, sent as `Authorization: Bearer <token>` to the repository's host only. Never stored past the job."
           },
           commit_sha: %Schema{type: :string, description: "The full commit SHA to check out."},
           ref: %Schema{
             type: :string,
             description:
               "The ref the commit belongs to, such as refs/heads/main. Shown in the dashboard and fetched when the server does not serve the commit by SHA."
           },
           name: %Schema{type: :string, description: "The job name. Defaults to job."},
           script: %Schema{
             type: :string,
             description: "The Bash script to run, up to 256 KiB. Runs with `set -eo pipefail` in a login shell."
           },
           env: @variables_schema,
           secrets: %{
             @variables_schema
             | description: "Variables like env, with their values masked in the job log."
           },
           timeout_minutes: %Schema{
             type: :integer,
             minimum: 1,
             maximum: APIJobs.max_timeout_minutes(),
             description: "Defaults to #{APIJobs.default_timeout_minutes()}."
           },
           idempotency_key: %Schema{
             type: :string,
             maxLength: 255,
             description:
               "Identifies the job in the account, such as <repository>:<commit>:<check>, so retries return the same job."
           }
         },
         required: [:profile, :repository_url, :commit_sha, :script]
       }},
    responses: %{
      created: {"Created runner job", "application/json", @runner_job_schema},
      ok: {"The job created earlier with the same idempotency key", "application/json", @runner_job_schema},
      bad_request: {"Missing or malformed fields", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      payment_required: {"The account's runner allowance is exhausted", "application/json", Error},
      unprocessable_entity: {"The profile does not exist or a field is invalid", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def create_job(%{assigns: %{selected_account: account}, body_params: body} = conn, _params) do
    attrs =
      Map.take(body, [
        :profile,
        :repository_url,
        :repository,
        :clone_token,
        :commit_sha,
        :ref,
        :name,
        :script,
        :env,
        :secrets,
        :timeout_minutes,
        :idempotency_key
      ])

    with true <- FeatureFlags.runners_enabled?(account),
         {:ok, job, outcome} <- APIJobs.create_job(account, attrs),
         {:ok, runner_job} <- Jobs.get_for_account(account.id, job.workflow_job_id) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(serialize_job(runner_job))
    else
      false ->
        runners_unavailable(conn)

      {:error, :allowance_exhausted} ->
        conn |> put_status(:payment_required) |> json(%{message: "The account's runner allowance is exhausted."})

      {:error, :unknown_profile} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "No runner profile matches the profile field."})

      {:error, {:invalid, field}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: "The #{field} field is invalid."})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{message: changeset_message(changeset)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Runner job not found."})
    end
  end

  operation(:cancel_job,
    summary: "Cancel a runner job created through the API.",
    description:
      "A job no runner has started is cancelled immediately. A running job stops within a few seconds and completes as cancelled. Cancelling a completed job changes nothing.",
    operation_id: "cancelRunnerJob",
    parameters:
      @account_parameters ++
        [workflow_job_id: [in: :path, type: :integer, required: true, description: "The workflow job identifier."]],
    responses: %{
      ok: {"The job after the request", "application/json", @runner_job_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"No API job with that identifier", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def cancel_job(%{assigns: %{selected_account: account}, params: %{workflow_job_id: workflow_job_id}} = conn, _params) do
    with true <- FeatureFlags.runners_enabled?(account),
         {:ok, _outcome} <- APIJobs.cancel_job(account.id, workflow_job_id),
         {:ok, runner_job} <- Jobs.get_for_account(account.id, workflow_job_id) do
      json(conn, serialize_job(runner_job))
    else
      false -> runners_unavailable(conn)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Runner job not found."})
    end
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
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

  operation(:catalog,
    summary: "List the machine shapes and Xcode versions runner profiles can use.",
    description:
      "Shapes are the vcpus and memory_gb pairs available per platform. Xcode versions apply to macOS profiles. Entries marked default are what the default profiles use.",
    operation_id: "getRunnerCatalog",
    parameters: @account_parameters,
    responses: %{
      ok: {"Runner catalog", "application/json", @catalog_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def catalog(%{assigns: %{selected_account: account}} = conn, _params) do
    if FeatureFlags.runners_enabled?(account) do
      json(conn, Profiles.catalog())
    else
      runners_unavailable(conn)
    end
  end

  operation(:create_profile,
    summary: "Create a runner profile.",
    description:
      "Creates a profile that pins a platform, a machine shape and, on macOS, an Xcode version. Workflows reference it in runs-on with the returned runs_on_label.",
    operation_id: "createRunnerProfile",
    parameters: @account_parameters,
    request_body:
      {"Runner profile", "application/json",
       %Schema{
         type: :object,
         properties:
           Map.merge(
             %{
               name: %Schema{
                 type: :string,
                 description:
                   "Up to 32 lowercase letters, digits, and hyphens, starting with a letter. runner, runners, and tuist are reserved."
               },
               platform: %Schema{type: :string, enum: ["linux", "macos"]}
             },
             @profile_change_properties
           ),
         required: [:name, :platform, :vcpus, :memory_gb]
       }},
    responses: %{
      created: {"Created runner profile", "application/json", @profile_schema},
      bad_request: {"Missing or malformed fields", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Runners are not enabled", "application/json", Error},
      unprocessable_entity:
        {"The profile is invalid or the account reached its profile limit", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def create_profile(%{assigns: %{selected_account: account}, body_params: body} = conn, _params) do
    with true <- FeatureFlags.runners_enabled?(account),
         {:ok, profile} <- Profiles.create(account, Map.take(body, [:name, :platform | @profile_change_fields])) do
      conn |> put_status(:created) |> json(serialize_profile(profile))
    else
      false -> runners_unavailable(conn)
      {:error, reason} -> profile_error(conn, reason)
    end
  end

  operation(:update_profile,
    summary: "Update a runner profile.",
    description:
      "Changes the profile's machine shape, Xcode version, or which jobs save its custom cache volume changes. Omitted fields keep their value; the name and platform can't change. Narrowing the cache saving policy discards pending saves it no longer allows.",
    operation_id: "updateRunnerProfile",
    parameters: @account_parameters ++ @profile_name_parameters,
    request_body: {"Profile changes", "application/json", %Schema{type: :object, properties: @profile_change_properties}},
    responses: %{
      ok: {"Updated runner profile", "application/json", @profile_schema},
      bad_request: {"Missing or malformed fields", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"The profile was not found or runners are not enabled", "application/json", Error},
      unprocessable_entity: {"The changes are invalid", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def update_profile(
        %{assigns: %{selected_account: account}, path_params: %{"profile_name" => name}, body_params: body} = conn,
        _params
      ) do
    with_profile(conn, account, name, fn profile ->
      case Profiles.update(profile, Map.take(body, @profile_change_fields)) do
        {:ok, profile} -> json(conn, serialize_profile(profile))
        {:error, reason} -> profile_error(conn, reason)
      end
    end)
  end

  operation(:delete_profile,
    summary: "Delete a runner profile.",
    description:
      "Jobs that request the profile's runs-on label stop being picked up; running jobs finish. Default profiles can't be deleted.",
    operation_id: "deleteRunnerProfile",
    parameters: @account_parameters ++ @profile_name_parameters,
    responses: %{
      no_content: "The runner profile was deleted",
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"The profile was not found or runners are not enabled", "application/json", Error},
      unprocessable_entity: {"The profile is a default profile", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def delete_profile(%{assigns: %{selected_account: account}, path_params: %{"profile_name" => name}} = conn, _params) do
    with_profile(conn, account, name, fn profile ->
      case Profiles.delete(profile) do
        {:ok, _profile} -> send_resp(conn, :no_content, "")
        {:error, reason} -> profile_error(conn, reason)
      end
    end)
  end

  defp with_profile(conn, account, name, fun) do
    with true <- FeatureFlags.runners_enabled?(account),
         %Profile{} = profile <- Profiles.get_by_name(account, name) do
      fun.(profile)
    else
      false -> runners_unavailable(conn)
      nil -> conn |> put_status(:not_found) |> json(%{message: "The runner profile was not found."})
    end
  end

  defp profile_error(conn, reason),
    do: conn |> put_status(:unprocessable_entity) |> json(%{message: Profiles.error_message(reason)})

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
    profile
    |> Map.take([
      :id,
      :name,
      :platform,
      :vcpus,
      :memory_gb,
      :xcode_version,
      :os_version,
      :protected,
      :cache_writer_all_branches,
      :cache_writer_default_branch,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:cache_writer_branches, profile.cache_writer_branches || [])
    |> Map.put(:runs_on_label, Profile.dispatch_label(profile))
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
