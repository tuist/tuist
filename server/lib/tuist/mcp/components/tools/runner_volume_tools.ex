defmodule Tuist.MCP.Components.Tools.RunnerVolumeTools do
  @moduledoc false
  alias Tuist.MCP.Components.Tools.RunnerTools
  alias Tuist.Runners.CacheVolumes.Query

  def execute(action, conn, args) do
    authorization =
      if action == :clear,
        do: RunnerTools.authorize_profiles_account(args, conn.assigns),
        else: RunnerTools.authorize_account(args, conn.assigns)

    with {:ok, account} <- authorization do
      case Query.run(action, account.id, args) do
        {:ok, data} ->
          {:ok, data}

        {:error, :not_found} ->
          {:error, "Runner volume or job not found."}

        {:error, :invalid_parameters} ->
          {:error,
           "Invalid identifier, pagination, sorting or time range. Use an ordered range of at most 90 days ending no later than now."}
      end
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListRunnerVolumes do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_runner_volumes",
    title: "List Runner Volumes",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:list)),
    output_schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:list))

  @impl EMCP.Tool
  def description,
    do:
      "List and sort runner volumes for an account. Optional name and repository filters match exactly and combine with AND."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:list, conn, args)
end

defmodule Tuist.MCP.Components.Tools.GetRunnerVolume do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_runner_volume",
    title: "Get Runner Volume",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:show)),
    output_schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:show))

  @impl EMCP.Tool
  def description, do: "Get volume repository, provider, platform, capacity, used space and last use."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:show, conn, args)
end

defmodule Tuist.MCP.Components.Tools.ListRunnerVolumeJobs do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_runner_volume_jobs",
    title: "List Runner Volume Jobs",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:jobs)),
    output_schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:jobs))

  @impl EMCP.Tool
  def description, do: "List volume job history. Cache status describes saving changes, not the job result."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:jobs, conn, args)
end

defmodule Tuist.MCP.Components.Tools.ListRunnerJobVolumes do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_runner_job_volumes",
    title: "List Runner Job Volumes",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:job_volumes)),
    output_schema:
      Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:job_volumes))

  @impl EMCP.Tool
  def description, do: "List the volumes mounted by a runner job."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:job_volumes, conn, args)
end

defmodule Tuist.MCP.Components.Tools.GetRunnerVolumeAnalytics do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_runner_volume_analytics",
    title: "Get Runner Volume Analytics",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:analytics)),
    output_schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:analytics))

  @impl EMCP.Tool
  def description,
    do:
      "Get range-based storage, hit rate, job runs and trends for an account or volume. Defaults to the last seven days; maximum range is 90 days. Unknown metrics remain null."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:analytics, conn, args)
end

defmodule Tuist.MCP.Components.Tools.ClearRunnerVolume do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "clear_runner_volume",
    title: "Clear Runner Volume",
    read_only_hint: false,
    destructive_hint: true,
    schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.inputs(:clear)),
    output_schema: Tuist.Runners.CacheVolumes.Schemas.json_schema(Tuist.Runners.CacheVolumes.Schemas.response(:clear))

  @impl EMCP.Tool
  def description,
    do:
      "Clear saved volume contents after user confirmation. This cannot be undone. Running jobs retain private copies but cannot save them; later jobs start empty. Requires account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.RunnerVolumeTools.execute(:clear, conn, args)
end
