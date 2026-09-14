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
  shared files several times over. A sharded run's shards each report the
  files they covered, and a file keeps the highest count any shard observed.
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
    coverage |> files() |> unique_totals() |> totals_attrs()
  end

  @doc """
  Folds a shard's `xcode_coverage` block into the merged run, after its files
  are stored. The totals are aggregated in ClickHouse over every shard's rows,
  read with sequential consistency since a plain read can miss rows another
  request inserted moments ago, and never drop below what the run already
  carries: two shards that report at the same time each see the other's rows
  or not, and the one that writes last must not shrink the run's coverage.
  """
  def merge_run_attrs(%Test{}, nil), do: %{}

  def merge_run_attrs(%Test{id: test_run_id} = existing, _coverage) do
    totals = stored_totals(test_run_id)

    totals_attrs(%{
      covered_lines: max(totals.covered_lines, existing.coverage_covered_lines || 0),
      executable_lines: max(totals.executable_lines, existing.coverage_executable_lines || 0)
    })
  end

  def insert_files(%Test{}, nil), do: :ok

  def insert_files(%Test{id: test_run_id, project_id: project_id}, coverage) do
    now = NaiveDateTime.utc_now()

    coverage
    |> files()
    |> Enum.map(
      &Map.merge(&1, %{id: UUIDv7.generate(), test_run_id: test_run_id, project_id: project_id, inserted_at: now})
    )
    |> Enum.chunk_every(5_000)
    |> Enum.each(&IngestRepo.insert_all(XcodeCoverageFile, &1))
  end

  @doc """
  The run's targets with their file count and line totals, least covered
  first. Aggregated in ClickHouse: a file's counts are collapsed across shards
  before they are summed into the target.
  """
  def targets_for_run(test_run_id) do
    ClickHouseRepo.all(
      from(f in subquery(per_file_query(test_run_id)),
        group_by: f.target_name,
        select: %{
          name: f.target_name,
          files_count: count(f.path),
          covered_lines: sum(f.covered_lines),
          executable_lines: sum(f.executable_lines)
        },
        order_by: [
          asc: fragment("sum(?) / greatest(sum(?), 1)", f.covered_lines, f.executable_lines),
          asc: f.target_name
        ]
      )
    )
  end

  @doc """
  One page of the run's files, least covered first. The page count is the
  targets' file counts summed, which the caller already has.
  """
  def list_files(test_run_id, page, page_size) do
    ClickHouseRepo.all(
      from(f in subquery(per_file_query(test_run_id)),
        order_by: [asc: fragment("? / greatest(?, 1)", f.covered_lines, f.executable_lines), asc: f.path],
        limit: ^page_size,
        offset: ^((page - 1) * page_size)
      )
    )
  end

  def percentage(_covered, 0), do: 0.0
  def percentage(_covered, nil), do: 0.0
  def percentage(covered, executable), do: Float.round(covered / executable * 100, 1)

  defp per_file_query(test_run_id) do
    from(f in XcodeCoverageFile,
      where: f.test_run_id == ^test_run_id,
      group_by: [f.target_name, f.path],
      select: %{
        target_name: f.target_name,
        path: f.path,
        covered_lines: max(f.covered_lines),
        executable_lines: max(f.executable_lines)
      }
    )
  end

  defp stored_totals(test_run_id) do
    per_path =
      from(f in XcodeCoverageFile,
        where: f.test_run_id == ^test_run_id,
        group_by: f.path,
        select: %{covered_lines: max(f.covered_lines), executable_lines: max(f.executable_lines)}
      )

    from(f in subquery(per_path),
      select: %{covered_lines: sum(f.covered_lines), executable_lines: sum(f.executable_lines)}
    )
    |> ClickHouseRepo.one(settings: [select_sequential_consistency: 1])
    |> case do
      nil -> %{covered_lines: 0, executable_lines: 0}
      totals -> Map.new(totals, fn {key, value} -> {key, value || 0} end)
    end
  end

  defp files(coverage) do
    for target <- Map.get(coverage, :targets) || [],
        file <- Map.get(target, :files) || [] do
      %{
        target_name: Map.get(target, :name) || "",
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

  defp totals_attrs(%{covered_lines: covered, executable_lines: executable}) do
    %{coverage_covered_lines: covered, coverage_executable_lines: executable}
  end
end
