defmodule Tuist.Tests.Coverage.Workers.RunFilesBackfillWorker do
  @moduledoc """
  Copies the run rows `coverage_files` held before `coverage_run_files` and
  `coverage_file_layouts` existed into them, so a commit measured before the
  release still reads its runs. Queued once by the PostgreSQL migration of
  the release that ships the tables, it runs a second pass an hour later for
  the reports that servers still on the previous release wrote meanwhile.

  It goes through `coverage_files` one partition and project at a time,
  copying the runs it holds more rows of than `coverage_run_files` does, and
  within them only the rows not copied yet, so a pass that failed halfway or
  ran twice copies nothing twice. A layout's id is a ClickHouse hash here,
  not the one `Tuist.Tests.Coverage.layout_id/1` computes, which only means a
  week the release starts in may hold a version twice.
  """
  use Oban.Worker, queue: :coverage_backfills, max_attempts: 20

  alias Tuist.ClickHouse.IndexMaterialization
  alias Tuist.IngestRepo

  require Logger

  @runs_per_copy 500
  @second_pass_delay_seconds 3600

  # A reader takes a layout by path and id, so a hash of the rest is enough.
  @layout_id """
  toUInt32(sipHash64(path, git_blob_id, line_numbers, function_names, function_line_numbers,
    function_executable_lines) % 4294967296)
  """

  # `Coverage.layout_epoch/2`: the path's own weekday on or before the report's,
  # as `coverage_run_files` derives it for its `epoch`.
  @epoch "toDate(inserted_at, 'UTC') - ((toUInt32(toDate(inserted_at, 'UTC')) - CRC32(path) % 7) % 7)"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()", [], log: false)

    copied =
      for partition <- IndexMaterialization.partition_ids(IngestRepo, database, "coverage_files"),
          project_id <- projects(partition),
          reduce: 0 do
        copied -> copied + copy(partition, project_id)
      end

    Logger.info("Coverage run rows: copied the rows of #{copied} runs")

    if Map.get(args, "pass", 1) == 1 do
      %{pass: 2} |> new(schedule_in: @second_pass_delay_seconds) |> Oban.insert!()
    end

    :ok
  end

  defp projects(partition) do
    "SELECT DISTINCT project_id FROM coverage_files WHERE _partition_id = {partition:String} AND scope_kind = 'run'"
    |> IngestRepo.query!(%{"partition" => partition})
    |> Map.fetch!(:rows)
    |> Enum.map(&hd/1)
  end

  defp copy(partition, project_id) do
    params = %{"partition" => partition, "project_id" => project_id}

    rows =
      """
      SELECT toString(test_run_id), count() FROM coverage_files
      WHERE project_id = {project_id:Int64} AND _partition_id = {partition:String} AND scope_kind = 'run'
      GROUP BY test_run_id
      """
      |> IngestRepo.query!(params)
      |> Map.fetch!(:rows)

    rows
    |> Enum.chunk_every(@runs_per_copy)
    |> Enum.flat_map(fn chunk ->
      copied = copied_rows(project_id, Enum.map(chunk, &hd/1))
      for [run_id, count] <- chunk, Map.get(copied, run_id, 0) < count, do: run_id
    end)
    |> Enum.chunk_every(@runs_per_copy)
    |> Enum.reduce(0, fn run_ids, total ->
      params = Map.put(params, "run_ids", run_ids)
      IngestRepo.query!(layouts_sql(), params)
      IngestRepo.query!(run_files_sql(), params)
      total + length(run_ids)
    end)
  end

  defp copied_rows(project_id, run_ids) do
    """
    SELECT toString(test_run_id), count() FROM coverage_run_files
    WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
    GROUP BY test_run_id
    """
    |> IngestRepo.query!(%{"project_id" => project_id, "run_ids" => run_ids})
    |> Map.fetch!(:rows)
    |> Map.new(fn [run_id, count] -> {run_id, count} end)
  end

  # The runs' rows `coverage_run_files` doesn't hold, by report and path.
  defp source_sql do
    """
    SELECT * FROM coverage_files
    WHERE project_id = {project_id:Int64} AND _partition_id = {partition:String} AND scope_kind = 'run'
      AND test_run_id IN {run_ids:Array(UUID)}
      AND (test_run_id, shard_index, inserted_at, path) NOT IN (
        SELECT test_run_id, shard_index, inserted_at, path FROM coverage_run_files
        WHERE project_id = {project_id:Int64} AND test_run_id IN {run_ids:Array(UUID)}
      )
    """
  end

  defp layouts_sql do
    """
    INSERT INTO coverage_file_layouts (project_id, epoch, path, layout_id, git_blob_id, line_numbers,
      function_names, function_line_numbers, function_executable_lines)
    SELECT project_id, #{@epoch} AS epoch, path, #{@layout_id} AS layout_id, git_blob_id,
      line_numbers, function_names, function_line_numbers, function_executable_lines
    FROM (#{source_sql()})
    LIMIT 1 BY epoch, path, layout_id
    """
  end

  defp run_files_sql do
    """
    INSERT INTO coverage_run_files (project_id, test_run_id, shard_index, path, layout_id, build_system,
      partial, in_repository, is_test, targets, git_commit_sha, covered_lines, executable_lines, execution_counts,
      function_execution_counts, function_covered_lines, inserted_at)
    SELECT project_id, test_run_id, shard_index, path, #{@layout_id}, build_system,
      partial, in_repository, is_test, targets, git_commit_sha, covered_lines, executable_lines,
      if(arrayExists(c -> c > 0, execution_counts), #{capped("execution_counts")}, []),
      if(arrayExists(c -> c > 0, function_execution_counts) OR arrayExists(c -> c > 0, function_covered_lines),
        #{capped("function_execution_counts")}, []),
      if(arrayExists(c -> c > 0, function_execution_counts) OR arrayExists(c -> c > 0, function_covered_lines),
        function_covered_lines, []),
      inserted_at
    FROM (#{source_sql()})
    """
  end

  # `coverage_run_files` holds counts as UInt32, capped as `Coverage.publish/4` caps them.
  defp capped(column), do: "arrayMap(c -> toUInt32(least(c, 4294967295)), #{column})"
end
