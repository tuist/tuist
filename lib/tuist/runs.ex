defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runs.Build
  alias Tuist.Runs.BuildIssue

  def get_build(id) do
    Repo.get(Build, id)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def create_build(attrs) do
    case %Build{}
         |> Build.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, build} ->
        issues =
          attrs.issues
          |> Enum.map(&Map.put(&1, :build_run_id, build.id))
          |> Enum.map(fn issue_attrs ->
            %{
              build_run_id: issue_attrs.build_run_id,
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
              ending_column: issue_attrs.ending_column
            }
          end)

        ClickHouseRepo.insert_all(
          BuildIssue,
          issues
        )

        {:ok, build}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def list_build_runs(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Build
    |> preload(^preload)
    |> Flop.validate_and_run!(attrs, for: Build)
  end

  def project_build_schemes(%Project{} = project) do
    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.scheme))
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -30, :day))
    |> distinct([b], b.scheme)
    |> Repo.all()
    |> Enum.map(& &1.scheme)
  end
end
