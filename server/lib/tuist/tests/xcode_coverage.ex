defmodule Tuist.Tests.XcodeCoverage do
  @moduledoc """
  Server half of Xcode code coverage.

  The client reads the coverage report `xcodebuild` wrote into the result
  bundle (`xccov view --report --json`) and sends it with the test run: every
  target the scheme gathered coverage for, and each source file in it with its
  covered and executable line counts. The rows land in `xcode_coverage_files`
  as reported, and the run carries two totals on `test_runs` so lists and
  trends never join the file table.

  The totals count each path once. `xccov` lists a file under every target
  that links it (a framework's source shows up again under the test bundle
  that links the framework statically), so summing the targets would count
  shared files several times over.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Test
  alias Tuist.Tests.XcodeCoverageFile

  @doc """
  Maps the `xcode_coverage` block a client reports with a test run onto the
  `test_runs` columns.
  """
  def run_attrs(nil), do: %{}

  def run_attrs(coverage) do
    totals = coverage |> files() |> unique_totals()

    %{
      coverage_covered_lines: totals.covered_lines,
      coverage_executable_lines: totals.executable_lines
    }
  end

  @doc """
  Folds a shard's `xcode_coverage` block into the merged run. Shards run
  disjoint tests against the same sources, so a file covered by several shards
  keeps the highest count any of them observed rather than the sum.
  """
  def merge_run_attrs(%Test{} = existing, nil), do: Map.take(existing, Map.keys(run_attrs(%{targets: []})))

  def merge_run_attrs(%Test{id: test_run_id}, coverage) do
    totals =
      test_run_id
      |> stored_files()
      |> Enum.concat(files(coverage))
      |> unique_totals()

    %{
      coverage_covered_lines: totals.covered_lines,
      coverage_executable_lines: totals.executable_lines
    }
  end

  def insert_files(%Test{}, nil), do: :ok

  def insert_files(%Test{id: test_run_id, project_id: project_id}, coverage) do
    now = NaiveDateTime.utc_now()

    rows =
      for target <- Map.get(coverage, :targets) || [],
          file <- Map.get(target, :files) || [] do
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          project_id: project_id,
          target_name: Map.get(target, :name) || "",
          path: Map.get(file, :path) || "",
          covered_lines: Map.get(file, :covered_lines) || 0,
          executable_lines: Map.get(file, :executable_lines) || 0,
          inserted_at: now
        }
      end

    rows
    |> Enum.chunk_every(5_000)
    |> Enum.each(&IngestRepo.insert_all(XcodeCoverageFile, &1))
  end

  @doc """
  The run's coverage grouped by target, each target listing its files sorted
  by ascending coverage so the least covered surface first. A sharded run's
  shards each report the file, so the highest count observed wins.
  """
  def targets_for_run(test_run_id) do
    test_run_id
    |> stored_files()
    |> Enum.group_by(& &1.target_name)
    |> Enum.map(fn {name, rows} ->
      files =
        rows
        |> Enum.group_by(& &1.path)
        |> Enum.map(fn {path, entries} ->
          %{
            path: path,
            covered_lines: entries |> Enum.map(& &1.covered_lines) |> Enum.max(),
            executable_lines: entries |> Enum.map(& &1.executable_lines) |> Enum.max()
          }
        end)
        |> Enum.sort_by(&{ratio(&1), &1.path})

      %{
        name: name,
        covered_lines: files |> Enum.map(& &1.covered_lines) |> Enum.sum(),
        executable_lines: files |> Enum.map(& &1.executable_lines) |> Enum.sum(),
        files: files
      }
    end)
    |> Enum.sort_by(&{ratio(&1), &1.name})
  end

  def ratio(%Test{coverage_covered_lines: covered, coverage_executable_lines: executable}) do
    ratio(%{covered_lines: covered, executable_lines: executable})
  end

  def ratio(%{executable_lines: 0}), do: 0.0
  def ratio(%{covered_lines: covered, executable_lines: executable}), do: covered / executable

  def percentage(entry), do: entry |> ratio() |> Kernel.*(100) |> Float.round(1)

  defp stored_files(test_run_id) do
    ClickHouseRepo.all(
      from(f in XcodeCoverageFile,
        where: f.test_run_id == ^test_run_id,
        select: %{
          target_name: f.target_name,
          path: f.path,
          covered_lines: f.covered_lines,
          executable_lines: f.executable_lines
        }
      )
    )
  end

  defp files(coverage) do
    for target <- Map.get(coverage, :targets) || [],
        file <- Map.get(target, :files) || [] do
      %{
        path: Map.get(file, :path) || "",
        covered_lines: Map.get(file, :covered_lines) || 0,
        executable_lines: Map.get(file, :executable_lines) || 0
      }
    end
  end

  defp unique_totals(files) do
    files
    |> Enum.group_by(& &1.path)
    |> Enum.reduce(%{covered_lines: 0, executable_lines: 0}, fn {_path, entries}, acc ->
      %{
        covered_lines: acc.covered_lines + (entries |> Enum.map(& &1.covered_lines) |> Enum.max()),
        executable_lines: acc.executable_lines + (entries |> Enum.map(& &1.executable_lines) |> Enum.max())
      }
    end)
  end
end
