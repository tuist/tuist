defmodule Tuist.MCP.Components.Tools.RunnerTools do
  @moduledoc false

  alias Tuist.FeatureFlags
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  def authorize_account(arguments, assigns) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, assigns, :read, :runners),
         true <- FeatureFlags.runners_enabled?(account) do
      {:ok, account}
    else
      false -> {:error, "Runners are not enabled for this account."}
      {:error, _message} = error -> error
    end
  end

  def authorize_profiles_account(arguments, assigns) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, assigns, :update, :account),
         true <- FeatureFlags.runners_enabled?(account) do
      {:ok, account}
    else
      false -> {:error, "Runners are not enabled for this account."}
      {:error, _message} = error -> error
    end
  end

  def job_schema do
    %{
      "type" => "object",
      "properties" => %{
        "workflow_job_id" => %{"type" => "integer"},
        "repository" => %{"type" => "string"},
        "workflow_run_id" => %{"type" => "integer"},
        "workflow_name" => %{"type" => "string"},
        "run_attempt" => %{"type" => "integer"},
        "job_name" => %{"type" => "string"},
        "head_branch" => %{"type" => "string"},
        "head_sha" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "conclusion" => %{"type" => "string"},
        "platform" => %{"type" => "string"},
        "vcpus" => %{"type" => "integer"},
        "memory_gb" => %{"type" => "integer"},
        "requested_dispatch_label" => %{"type" => "string"},
        "enqueued_at" => %{"type" => "string"},
        "claimed_at" => %{"type" => ["string", "null"]},
        "started_at" => %{"type" => ["string", "null"]},
        "completed_at" => %{"type" => ["string", "null"]},
        "log_archived_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "workflow_job_id",
        "repository",
        "workflow_run_id",
        "workflow_name",
        "run_attempt",
        "job_name",
        "head_branch",
        "head_sha",
        "status",
        "conclusion",
        "platform",
        "vcpus",
        "memory_gb",
        "requested_dispatch_label",
        "enqueued_at",
        "claimed_at",
        "started_at",
        "completed_at",
        "log_archived_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def workflow_schema do
    %{
      "type" => "object",
      "properties" => %{
        "workflow_name" => %{"type" => "string"},
        "repository" => %{"type" => "string"},
        "total_jobs" => %{"type" => "integer"},
        "success_count" => %{"type" => "integer"},
        "failure_count" => %{"type" => "integer"},
        "cancelled_count" => %{"type" => "integer"},
        "skipped_count" => %{"type" => "integer"},
        "in_progress_count" => %{"type" => "integer"},
        "avg_duration_ms" => %{"type" => ["number", "null"]},
        "last_run_at" => %{"type" => "string"}
      },
      "required" => [
        "workflow_name",
        "repository",
        "total_jobs",
        "success_count",
        "failure_count",
        "cancelled_count",
        "skipped_count",
        "in_progress_count",
        "avg_duration_ms",
        "last_run_at"
      ],
      "additionalProperties" => false
    }
  end

  def profile_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "name" => %{"type" => "string"},
        "platform" => %{"type" => "string", "enum" => ["linux", "macos"]},
        "vcpus" => %{"type" => "integer"},
        "memory_gb" => %{"type" => "integer"},
        "xcode_version" => %{"type" => ["string", "null"]},
        "protected" => %{"type" => "boolean"},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "platform",
        "vcpus",
        "memory_gb",
        "xcode_version",
        "protected",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def job_step_schema do
    %{
      "type" => "object",
      "properties" => %{
        "number" => %{"type" => "integer"},
        "name" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "conclusion" => %{"type" => "string"},
        "started_at" => %{"type" => ["string", "null"]},
        "completed_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["number", "name", "status", "conclusion", "started_at", "completed_at"],
      "additionalProperties" => false
    }
  end

  def job_metric_schema do
    %{
      "type" => "object",
      "properties" => %{
        "timestamp" => %{"type" => "number"},
        "cpu_usage_percent" => %{"type" => "number"},
        "cpu_iowait_percent" => %{"type" => "number"},
        "memory_used_bytes" => %{"type" => "integer"},
        "memory_total_bytes" => %{"type" => "integer"},
        "network_bytes_in" => %{"type" => "integer"},
        "network_bytes_out" => %{"type" => "integer"},
        "disk_used_bytes" => %{"type" => "integer"},
        "disk_total_bytes" => %{"type" => "integer"},
        # Nullable: absent on samples from runner images predating the field.
        # Not `disk_total_bytes - disk_used_bytes` — on APFS those do not
        # subtract, so this is the only trustworthy capacity figure.
        "disk_available_bytes" => %{"type" => ["integer", "null"]}
      },
      "required" => [
        "timestamp",
        "cpu_usage_percent",
        "cpu_iowait_percent",
        "memory_used_bytes",
        "memory_total_bytes",
        "network_bytes_in",
        "network_bytes_out",
        "disk_used_bytes",
        "disk_total_bytes",
        "disk_available_bytes"
      ],
      "additionalProperties" => false
    }
  end

  def job_log_schema do
    %{
      "type" => "object",
      "properties" => %{
        "line_number" => %{"type" => "integer"},
        "ts" => %{"type" => ["string", "null"]},
        "message" => %{"type" => "string"}
      },
      "required" => ["line_number", "ts", "message"],
      "additionalProperties" => false
    }
  end

  def serialize_job(job) do
    %{
      workflow_job_id: job.workflow_job_id,
      repository: job.repository,
      workflow_run_id: job.workflow_run_id,
      workflow_name: job.workflow_name,
      run_attempt: job.run_attempt,
      job_name: job.job_name,
      head_branch: job.head_branch,
      head_sha: job.head_sha,
      status: job.status,
      conclusion: job.conclusion,
      platform: job.platform,
      vcpus: job.vcpus,
      memory_gb: job.memory_gb,
      requested_dispatch_label: job.requested_dispatch_label,
      enqueued_at: Formatter.iso8601(job.enqueued_at),
      claimed_at: Formatter.iso8601(job.claimed_at),
      started_at: Formatter.iso8601(job.started_at),
      completed_at: Formatter.iso8601(job.completed_at),
      log_archived_at: Formatter.iso8601(job.log_archived_at),
      updated_at: Formatter.iso8601(job.updated_at)
    }
  end

  def serialize_workflow(workflow) do
    %{
      workflow_name: workflow.workflow_name,
      repository: workflow.repository,
      total_jobs: workflow.total_jobs,
      success_count: workflow.success_count,
      failure_count: workflow.failure_count,
      cancelled_count: workflow.cancelled_count,
      skipped_count: workflow.skipped_count,
      in_progress_count: workflow.in_progress_count,
      avg_duration_ms: workflow.avg_duration_ms,
      last_run_at: Formatter.iso8601(workflow.last_run_at)
    }
  end

  def serialize_profile(profile) do
    %{
      id: profile.id,
      name: profile.name,
      platform: to_string(profile.platform),
      vcpus: profile.vcpus,
      memory_gb: profile.memory_gb,
      xcode_version: profile.xcode_version,
      protected: profile.protected,
      inserted_at: Formatter.iso8601(profile.inserted_at),
      updated_at: Formatter.iso8601(profile.updated_at)
    }
  end

  def serialize_job_step(step) do
    %{
      number: step.number,
      name: step.name,
      status: step.status,
      conclusion: step.conclusion,
      started_at: Formatter.iso8601(step.started_at),
      completed_at: Formatter.iso8601(step.completed_at)
    }
  end

  def serialize_job_metric(metric), do: metric

  def serialize_job_log(line) do
    %{line_number: line.line_number, ts: Formatter.iso8601(line.ts), message: line.message}
  end

  def with_job(account, workflow_job_id, fun) do
    case Tuist.Runners.Jobs.get_for_account(account.id, workflow_job_id) do
      {:ok, job} -> fun.(job)
      {:error, :not_found} -> {:error, "Runner job not found: #{workflow_job_id}"}
    end
  end

  def jobs_options(arguments) do
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
      fn key -> if value = Map.get(arguments, Atom.to_string(key)), do: [{key, value}], else: [] end
    )
  end

  def workflows_options(arguments) do
    Enum.flat_map([:repository, :workflow_name, :head_branch, :platform, :sort_by, :sort_order], fn key ->
      if value = Map.get(arguments, Atom.to_string(key)), do: [{key, value}], else: []
    end)
  end

  def pagination_metadata(page, page_size, total_count) do
    total_pages = ceil(total_count / page_size)

    %{
      has_next_page: page < total_pages,
      has_previous_page: page > 1,
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    }
  end
end

defmodule Tuist.MCP.Components.Tools.ListRunnerJobs do
  @moduledoc """
  List CI runner jobs for an account.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_jobs",
    title: "List Runner Jobs",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, maximum: 100)."},
        "status" => %{"type" => "string", "enum" => ["queued", "claimed", "running", "completed"]},
        "conclusion" => %{"type" => "string", "enum" => ["success", "failure", "cancelled", "skipped"]},
        "repository" => %{"type" => "string"},
        "workflow_name" => %{"type" => "string"},
        "job_name" => %{"type" => "string"},
        "head_branch" => %{"type" => "string"},
        "platform" => %{"type" => "string", "enum" => ["linux", "macos"]},
        "search" => %{"type" => "string"},
        "sort_by" => %{"type" => "string", "enum" => ["enqueued", "job", "workflow", "duration"]},
        "sort_order" => %{"type" => "string", "enum" => ["asc", "desc"]}
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "jobs" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.job_schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["jobs", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.Jobs

  @impl EMCP.Tool
  def description, do: "List CI runner jobs for an account."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns) do
      page = MCPTool.page(arguments)
      page_size = MCPTool.page_size(arguments)
      base_options = RunnerTools.jobs_options(arguments)
      total_count = Jobs.count_for_account(account.id, base_options)

      jobs =
        Jobs.list_for_account(
          account.id,
          base_options ++ [limit: page_size, offset: (page - 1) * page_size]
        )

      MCPTool.json_response(
        %{
          jobs: Enum.map(jobs, &RunnerTools.serialize_job/1),
          pagination_metadata: RunnerTools.pagination_metadata(page, page_size, total_count)
        },
        __MODULE__
      )
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetRunnerJob do
  @moduledoc """
  Get a CI runner job for an account.
  """

  use Tuist.MCP.Tool,
    name: "get_runner_job",
    title: "Get Runner Job",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "workflow_job_id" => %{"type" => "integer", "description" => "The workflow job identifier."}
      },
      "required" => ["account_handle", "workflow_job_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.RunnerTools.job_schema()

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.Jobs

  @impl EMCP.Tool
  def description, do: "Get a CI runner job for an account."

  @impl EMCP.Tool
  def call(conn, %{"workflow_job_id" => workflow_job_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns),
         {:ok, job} <- Jobs.get_for_account(account.id, workflow_job_id) do
      MCPTool.json_response(RunnerTools.serialize_job(job), __MODULE__)
    else
      {:error, :not_found} -> EMCP.Tool.error("Runner job not found: #{workflow_job_id}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide account_handle and workflow_job_id.")
end

defmodule Tuist.MCP.Components.Tools.ListRunnerWorkflows do
  @moduledoc """
  List CI runner workflows for an account.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_workflows",
    title: "List Runner Workflows",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, maximum: 100)."},
        "repository" => %{"type" => "string"},
        "workflow_name" => %{"type" => "string"},
        "head_branch" => %{"type" => "string"},
        "platform" => %{"type" => "string", "enum" => ["linux", "macos"]},
        "sort_by" => %{"type" => "string", "enum" => ["workflow", "success_rate", "jobs", "avg_duration"]},
        "sort_order" => %{"type" => "string", "enum" => ["asc", "desc"]}
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "workflows" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.workflow_schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["workflows", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.Jobs

  @impl EMCP.Tool
  def description, do: "List CI runner workflows for an account."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns) do
      page = MCPTool.page(arguments)
      page_size = MCPTool.page_size(arguments)
      base_options = RunnerTools.workflows_options(arguments)
      total_count = Jobs.count_workflows_for_account(account.id, base_options)

      workflows =
        Jobs.list_workflows_for_account(
          account.id,
          base_options ++ [limit: page_size, offset: (page - 1) * page_size]
        )

      MCPTool.json_response(
        %{
          workflows: Enum.map(workflows, &RunnerTools.serialize_workflow/1),
          pagination_metadata: RunnerTools.pagination_metadata(page, page_size, total_count)
        },
        __MODULE__
      )
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListRunnerProfiles do
  @moduledoc """
  List CI runner profiles for an account.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_profiles",
    title: "List Runner Profiles",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."}
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "profiles" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.profile_schema()}
      },
      "required" => ["profiles"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.Profiles

  @impl EMCP.Tool
  def description, do: "List CI runner profiles for an account."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_profiles_account(arguments, conn.assigns) do
      profiles = account |> Profiles.list_for_account() |> Enum.map(&RunnerTools.serialize_profile/1)
      MCPTool.json_response(%{profiles: profiles}, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListRunnerJobSteps do
  @moduledoc """
  List the steps recorded for a CI runner job.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_job_steps",
    title: "List Runner Job Steps",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "workflow_job_id" => %{"type" => "integer", "description" => "The workflow job identifier."}
      },
      "required" => ["account_handle", "workflow_job_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "steps" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.job_step_schema()}
      },
      "required" => ["steps"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.JobSteps

  @impl EMCP.Tool
  def description, do: "List the steps recorded for a CI runner job."

  @impl EMCP.Tool
  def call(conn, %{"workflow_job_id" => workflow_job_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns),
         {:ok, response} <-
           RunnerTools.with_job(account, workflow_job_id, fn job ->
             {:ok, %{steps: Enum.map(JobSteps.list_for_job(job.workflow_job_id), &RunnerTools.serialize_job_step/1)}}
           end) do
      MCPTool.json_response(response, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide account_handle and workflow_job_id.")
end

defmodule Tuist.MCP.Components.Tools.ListRunnerJobMetrics do
  @moduledoc """
  List machine metrics recorded for a CI runner job.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_job_metrics",
    title: "List Runner Job Metrics",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "workflow_job_id" => %{"type" => "integer", "description" => "The workflow job identifier."}
      },
      "required" => ["account_handle", "workflow_job_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "metrics" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.job_metric_schema()}
      },
      "required" => ["metrics"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.JobMetrics

  @impl EMCP.Tool
  def description, do: "List machine metrics recorded for a CI runner job."

  @impl EMCP.Tool
  def call(conn, %{"workflow_job_id" => workflow_job_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns),
         {:ok, response} <-
           RunnerTools.with_job(account, workflow_job_id, fn job ->
             {:ok,
              %{metrics: Enum.map(JobMetrics.list_for_job(job.workflow_job_id), &RunnerTools.serialize_job_metric/1)}}
           end) do
      MCPTool.json_response(response, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide account_handle and workflow_job_id.")
end

defmodule Tuist.MCP.Components.Tools.ListRunnerJobLogs do
  @moduledoc """
  List captured log lines for a CI runner job.
  """

  use Tuist.MCP.Tool,
    name: "list_runner_job_logs",
    title: "List Runner Job Logs",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "workflow_job_id" => %{"type" => "integer", "description" => "The workflow job identifier."},
        "offset" => %{"type" => "integer", "description" => "Zero-based log-line offset."},
        "limit" => %{"type" => "integer", "description" => "Maximum number of lines, up to 500."}
      },
      "required" => ["account_handle", "workflow_job_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "lines" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.RunnerTools.job_log_schema()}
      },
      "required" => ["lines"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Runners.JobLogs

  @impl EMCP.Tool
  def description, do: "List captured log lines for a CI runner job."

  @impl EMCP.Tool
  def call(conn, %{"workflow_job_id" => workflow_job_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- RunnerTools.authorize_account(arguments, conn.assigns),
         {:ok, response} <-
           RunnerTools.with_job(account, workflow_job_id, fn job ->
             limit = arguments |> Map.get("limit", 200) |> max(1) |> min(500)
             offset = arguments |> Map.get("offset", 0) |> max(0)

             {:ok,
              %{
                lines:
                  job.workflow_job_id
                  |> JobLogs.list_for_job(limit: limit, offset: offset)
                  |> Enum.map(&RunnerTools.serialize_job_log/1)
              }}
           end) do
      MCPTool.json_response(response, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide account_handle and workflow_job_id.")
end
