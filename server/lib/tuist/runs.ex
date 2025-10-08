defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.ClickHouseFlop
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runs.Build
  alias Tuist.Runs.BuildBuffer
  alias Tuist.Runs.BuildFile
  alias Tuist.Runs.BuildFileBuffer
  alias Tuist.Runs.BuildIssue
  alias Tuist.Runs.BuildIssueBuffer
  alias Tuist.Runs.BuildTarget
  alias Tuist.Runs.BuildTargetBuffer

  def get_build(id) do
    Build
    |> where([b], b.id == ^id)
    |> ClickHouseRepo.one()
  end

  def create_build(attrs) do
    build_attrs = Build.changeset(attrs)
    build = struct(Build, build_attrs)

    {:ok, _} = BuildBuffer.insert(build)

    issues = Map.get(attrs, :issues, [])
    files = Map.get(attrs, :files, [])
    targets = Map.get(attrs, :targets, [])

    create_build_issues(build, issues)
    create_build_files(build, files)
    create_build_targets(build, targets)

    build = Repo.preload(build, project: :account)

    Tuist.PubSub.broadcast(
      build,
      "#{build.project.account.name}/#{build.project.name}",
      :build_created
    )

    {:ok, build}
  end

  defp create_build_files(build, files) do
    files =
      Enum.map(files, fn file_attrs ->
        %{
          build_run_id: build.id,
          type:
            case file_attrs.type do
              :swift -> 0
              :c -> 1
            end,
          path: file_attrs.path,
          target: file_attrs.target,
          project: file_attrs.project,
          compilation_duration: file_attrs.compilation_duration,
          inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
        }
      end)

    BuildFileBuffer.insert(files)
  end

  defp create_build_targets(build, targets) do
    targets = Enum.map(targets, &BuildTarget.changeset(build.id, &1))

    BuildTargetBuffer.insert(targets)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp create_build_issues(build, issues) do
    issues =
      Enum.map(issues, fn issue_attrs ->
        %{
          build_run_id: build.id,
          type:
            case issue_attrs.type do
              :warning -> 0
              :error -> 1
            end,
          target: issue_attrs.target,
          project: issue_attrs.project,
          title: issue_attrs.title,
          signature: issue_attrs.signature,
          step_type:
            case issue_attrs.step_type do
              :c_compilation -> 0
              :swift_compilation -> 1
              :script_execution -> 2
              :create_static_library -> 3
              :linker -> 4
              :copy_swift_libs -> 5
              :compile_assets_catalog -> 6
              :compile_storyboard -> 7
              :write_auxiliary_file -> 8
              :link_storyboards -> 9
              :copy_resource_file -> 10
              :merge_swift_module -> 11
              :xib_compilation -> 12
              :swift_aggregated_compilation -> 13
              :precompile_bridging_header -> 14
              :other -> 15
              :validate_embedded_binary -> 16
              :validate -> 17
            end,
          path: Map.get(issue_attrs, :path),
          message: Map.get(issue_attrs, :message),
          starting_line: issue_attrs.starting_line,
          ending_line: issue_attrs.ending_line,
          starting_column: issue_attrs.starting_column,
          ending_column: issue_attrs.ending_column,
          inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
        }
      end)

    BuildIssueBuffer.insert(issues)
  end

  def list_build_files(attrs) do
    ClickHouseFlop.validate_and_run!(BuildFile, attrs, for: BuildFile)
  end

  def list_build_targets(attrs) do
    ClickHouseFlop.validate_and_run!(BuildTarget, attrs, for: BuildTarget)
  end

  def list_build_runs(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    {builds, meta} = ClickHouseFlop.validate_and_run!(Build, attrs, for: Build)
    {Repo.preload(builds, preload), meta}
  end

  def recent_build_status_counts(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)
    order = Keyword.get(opts, :order, :desc)

    subquery =
      from(b in Build)
      |> where([b], b.project_id == ^project_id)
      |> order_by([b], [{^order, b.inserted_at}])
      |> limit(^limit)
      |> select([b], b.status)

    from(s in subquery(subquery))
    |> select([s], %{
      successful_count: fragment("countIf(? = 0)", s.status),
      failed_count: fragment("countIf(? = 1)", s.status)
    })
    |> ClickHouseRepo.one()
  end

  def project_build_schemes(%Project{} = project) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()

    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.scheme))
    |> where([b], b.inserted_at > ^cutoff)
    |> distinct([b], b.scheme)
    |> select([b], b.scheme)
    |> ClickHouseRepo.all()
  end

  def project_build_configurations(%Project{} = project) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()

    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.configuration))
    |> where([b], b.inserted_at > ^cutoff)
    |> distinct([b], b.configuration)
    |> select([b], b.configuration)
    |> ClickHouseRepo.all()
  end

  @doc """
  Constructs a CI run URL based on the CI provider and metadata.
  Returns nil if the build doesn't have complete CI information.
  """
  def build_ci_run_url(%Build{} = build) do
    case {build.ci_provider, build.ci_run_id, build.ci_project_handle} do
      {:github, run_id, project_handle} when not is_nil(run_id) and not is_nil(project_handle) ->
        "https://github.com/#{project_handle}/actions/runs/#{run_id}"

      {:gitlab, pipeline_id, project_path} when not is_nil(pipeline_id) and not is_nil(project_path) ->
        host = build.ci_host || "gitlab.com"
        "https://#{host}/#{project_path}/-/pipelines/#{pipeline_id}"

      {:bitrise, build_slug, _app_slug} when not is_nil(build_slug) ->
        "https://app.bitrise.io/build/#{build_slug}"

      {:circleci, build_num, project_handle} when not is_nil(build_num) and not is_nil(project_handle) ->
        "https://app.circleci.com/pipelines/github/#{project_handle}/#{build_num}"

      {:buildkite, build_number, project_handle} when not is_nil(build_number) and not is_nil(project_handle) ->
        "https://buildkite.com/#{project_handle}/builds/#{build_number}"

      {:codemagic, build_id, project_id} when not is_nil(build_id) and not is_nil(project_id) ->
        "https://codemagic.io/app/#{project_id}/build/#{build_id}"

      _ ->
        nil
    end
  end
end
