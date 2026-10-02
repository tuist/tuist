defmodule Tuist.Mix do
  @moduledoc """
  Context module for Mix (Elixir) compile-time analytics.

  All data is stored in ClickHouse. `create_build/1` inserts the build
  record plus each captured diagnostic through the same Bufferable
  pipeline used for Gradle and Xcode analytics.
  """

  import Ecto.Query

  alias Tuist.Builds.Build, as: BuildRun
  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.Mix.Build
  alias Tuist.Mix.CompiledFile
  alias Tuist.Mix.Diagnostic
  alias Tuist.Mix.Step

  @doc """
  Fetches a Mix build by id, scoped to a project when `:project_id` is given.
  """
  def get_build(id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        query = from(b in Build, where: b.id == ^uuid, limit: 1)

        query =
          case Keyword.get(opts, :project_id) do
            nil -> query
            project_id -> from(b in query, where: b.project_id == ^project_id)
          end

        case ClickHouseRepo.one(query) do
          nil -> {:error, :not_found}
          build -> {:ok, build}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the project's most recent Mix builds, newest first.
  """
  def list_recent_builds(project_id, limit) do
    ClickHouseRepo.all(
      from(b in Build,
        where: b.project_id == ^project_id,
        order_by: [desc: b.inserted_at],
        limit: ^limit
      )
    )
  end

  @doc """
  Lists a project's Mix builds with Flop pagination, filtering, and sorting.
  """
  def list_builds(project_id, flop_params \\ %{}) do
    Tuist.ClickHouseFlop.validate_and_run!(
      from(b in Build, where: b.project_id == ^project_id),
      flop_params,
      for: Build
    )
  end

  @doc """
  Returns every diagnostic recorded for a build, oldest first. Scoped to the
  build's project as well as its id: the id is chosen by the client.
  """
  def list_diagnostics(%{id: build_id, project_id: project_id}) do
    ClickHouseRepo.all(
      from(d in Diagnostic,
        where: d.project_id == ^project_id and d.build_id == ^build_id,
        order_by: [asc: d.severity, asc: d.file, asc: d.line]
      )
    )
  end

  # What one build may carry. The API schema rejects more; these are the same
  # limits for callers that reach the context directly.
  @max_files 20_000
  @max_steps 50_000
  @max_diagnostics 5_000
  @max_machine_metrics 20_000
  @max_nested 5_000
  @uint32 4_294_967_295
  @int64 9_223_372_036_854_775_807
  # Seconds since the epoch, far past any real clock. Larger values overflow
  # when converted to milliseconds.
  @max_timestamp 100_000_000_000

  def limits do
    %{
      files: @max_files,
      steps: @max_steps,
      diagnostics: @max_diagnostics,
      machine_metrics: @max_machine_metrics,
      nested: @max_nested,
      uint32: @uint32,
      int64: @int64,
      timestamp: @max_timestamp
    }
  end

  @breakdown_orders %{
    "compile-duration" => "compile_duration_ms DESC, name ASC",
    "dependents" => "compile_dependents_count DESC, name ASC",
    "dependencies" => "compile_dependencies_count DESC, name ASC",
    "name" => "name ASC"
  }

  @doc """
  Returns one page of the files, or of the modules, compiled during a build,
  with their place in the dependency graph:

    * `compile_dependencies_count` — how many project files the file needs
      before it can finish compiling (`compile` and `export` dependencies).
    * `compile_dependents_count` — how many files of this build need it
      before they can finish compiling. A slow file with many dependents
      holds the parallel compiler back.

  Searching, sorting and paging happen in the database, so a build with many
  thousands of files costs a page, not the build.

  ## Options
    * `:by` — `:file` (default) or `:module`: a file defining several modules
      appears once per module, with the file's numbers.
    * `:search` — keeps the rows whose name contains it, ignoring case.
    * `:sort_by` — `"compile-duration"` (default), `"dependents"`,
      `"dependencies"` or `"name"`.
    * `:page` (default 1) and `:page_size` (default 20).

  Returns `%{rows: [...], total: count}`.
  """
  def compiled_files_page(%{id: build_id, project_id: project_id}, opts \\ []) do
    by_module? = Keyword.get(opts, :by, :file) == :module
    page_size = Keyword.get(opts, :page_size, 20)
    order = Map.get(@breakdown_orders, Keyword.get(opts, :sort_by), @breakdown_orders["compile-duration"])

    params = %{
      project_id: project_id,
      build_id: build_id,
      search: Keyword.get(opts, :search) || "",
      limit: page_size,
      offset: (max(Keyword.get(opts, :page, 1), 1) - 1) * page_size
    }

    # A row is a file, or a module of a file when listing modules.
    name = if by_module?, do: "module", else: "f.path"
    unnest = if by_module?, do: "ARRAY JOIN f.modules AS module", else: ""

    filter = """
    WHERE f.project_id = {project_id:Int64}
      AND f.build_id = {build_id:UUID}
      AND positionCaseInsensitive(#{name}, {search:String}) > 0
    """

    rows_query = """
    WITH dependents AS (
      SELECT dependency AS path, count() AS dependents
      FROM (
        SELECT arrayJoin(
          arrayFilter((path, kind) -> kind IN ('compile', 'export'), dependency_paths, dependency_kinds)
        ) AS dependency
        FROM mix_compiled_files
        WHERE project_id = {project_id:Int64} AND build_id = {build_id:UUID}
      )
      GROUP BY dependency
    )
    SELECT
      #{name} AS name,
      f.path AS path,
      f.compile_duration_ms AS compile_duration_ms,
      arrayCount(kind -> kind IN ('compile', 'export'), f.dependency_kinds) AS compile_dependencies_count,
      d.dependents AS compile_dependents_count
    FROM mix_compiled_files AS f
    #{unnest}
    LEFT JOIN dependents AS d ON d.path = f.path
    #{filter}
    ORDER BY #{order}
    LIMIT {limit:UInt32} OFFSET {offset:UInt32}
    """

    count_query = "SELECT count() FROM mix_compiled_files AS f #{unnest} #{filter}"

    {:ok, %{rows: rows}} = ClickHouseRepo.query(rows_query, params)
    {:ok, %{rows: [[total]]}} = ClickHouseRepo.query(count_query, Map.take(params, [:project_id, :build_id, :search]))

    %{
      total: total,
      rows:
        Enum.map(rows, fn [name, path, compile_duration_ms, dependencies, dependents] ->
          %{
            name: name,
            path: path,
            compile_duration_ms: compile_duration_ms,
            compile_dependencies_count: dependencies,
            compile_dependents_count: dependents
          }
        end)
    }
  end

  @doc """
  Whether the build recorded any compiled file.
  """
  def compiled_files?(%{id: build_id, project_id: project_id}) do
    ClickHouseRepo.exists?(from(f in CompiledFile, where: f.project_id == ^project_id and f.build_id == ^build_id))
  end

  @doc """
  Returns every machine-metric sample recorded for a build, oldest first.
  Scoped to the build's project as well as its id: the id is chosen by the
  client, and nothing stops two projects from choosing the same one.
  """
  def list_machine_metrics(%{id: build_id, project_id: project_id}) do
    ClickHouseRepo.all(
      from(m in BuildMachineMetric,
        where: m.mix_build_id == ^build_id and m.project_id == ^project_id,
        order_by: [asc: m.timestamp]
      )
    )
  end

  @doc """
  Creates a Mix compile build with associated diagnostics.

  ## Parameters
    * `attrs` — build attributes:
      * `:id` — client-generated UUID for the build (required)
      * `:project_id` — the project id (required)
      * `:account_id` — the account id (required)
      * `:duration_ms` — total compile duration in milliseconds (required)
      * `:status` — `"success"` or `"failure"` (required)
      * `:is_ci` — boolean, defaults to false
      * `:elixir_version`, `:otp_version`, `:mix_env` — strings, optional
      * `:git_branch`, `:git_commit_sha`, `:git_ref`,
        `:git_remote_url_origin` — strings, optional
      * `:ci_provider`, `:ci_run_id`, `:ci_project_handle` — strings, optional
      * `:contract_version` — string, optional
      * `:started_at` — `%DateTime{}` or ISO 8601 string, optional
      * `:custom_tags` — list of strings, optional
      * `:custom_values` — map of string → string, optional
      * `:diagnostics` — list of diagnostic maps (see below), optional
      * `:files` — per-file compile profile: `path`, `start_offset_ms`,
        `compile_duration_ms`, `wait_duration_ms`, `modules`, `dependencies`
        (`path`, `kind`) and `waits` (`duration_ms`, `start_offset_ms`),
        optional
      * `:steps` — the work besides compiling files: `category`
        (`type_check`, `write`, `compiler` or `other`), `title`, `path`,
        `start_offset_ms` and `duration_ms`, optional

  Each diagnostic map:
      %{severity: "warning" | "error", file: string, module: string,
        message: string, line: integer | nil, column: integer | nil,
        compiler: string}

  ## Returns
    * `{:ok, build_id}` on success
    * `{:error, reason}` when the custom metadata is invalid
  """
  def create_build(attrs) do
    with :ok <-
           BuildRun.validate_custom_metadata(
             Map.get(attrs, :custom_tags, []),
             Map.get(attrs, :custom_values, %{})
           ) do
      # Scoped to the project: another project may have chosen the same id,
      # which is fine, since every row of a build carries its project.
      case get_build(attrs.id, project_id: attrs.project_id) do
        {:error, :not_found} -> insert_build(attrs)
        # The client retried a report it had already delivered.
        {:ok, _build} -> {:ok, attrs.id}
      end
    end
  end

  defp insert_build(attrs) do
    now = Map.get(attrs, :inserted_at) || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    build_id = attrs.id
    diagnostics = attrs |> Map.get(:diagnostics, []) |> Enum.take(@max_diagnostics)

    counts = diagnostic_counts(diagnostics)
    build_entry = build_entry(attrs, build_id, counts, now)

    Build.Buffer.insert(build_entry)

    insert_diagnostics(build_id, attrs.project_id, diagnostics, now)

    insert_machine_metrics(
      build_id,
      attrs.project_id,
      attrs |> Map.get(:machine_metrics, []) |> Enum.take(@max_machine_metrics),
      now
    )

    insert_compiled_files(build_id, attrs.project_id, attrs |> Map.get(:files, []) |> Enum.take(@max_files), now)
    insert_steps(build_id, attrs.project_id, attrs |> Map.get(:steps, []) |> Enum.take(@max_steps), now)

    {:ok, build_id}
  end

  @build_string_fields [
    :elixir_version,
    :otp_version,
    :mix_env,
    :git_branch,
    :git_commit_sha,
    :git_ref,
    :git_remote_url_origin,
    :ci_provider,
    :ci_run_id,
    :ci_project_handle,
    :ci_host,
    :contract_version
  ]

  defp build_entry(attrs, build_id, counts, now) do
    @build_string_fields
    |> Map.new(&{&1, Map.get(attrs, &1) || ""})
    |> Map.merge(%{
      id: build_id,
      project_id: attrs.project_id,
      account_id: attrs.account_id,
      duration_ms: attrs |> Map.get(:duration_ms, 0) |> max(0) |> min(@int64),
      status: attrs.status,
      is_ci: Map.get(attrs, :is_ci, false),
      custom_tags: Map.get(attrs, :custom_tags, []),
      custom_values: Map.get(attrs, :custom_values, %{}),
      started_at: to_naive_datetime(Map.get(attrs, :started_at)),
      diagnostics_error_count: counts.errors,
      diagnostics_warning_count: counts.warnings,
      inserted_at: now
    })
  end

  defp diagnostic_counts(diagnostics) do
    Enum.reduce(diagnostics, %{errors: 0, warnings: 0}, fn diagnostic, acc ->
      case diagnostic_severity(diagnostic) do
        "error" -> Map.update!(acc, :errors, &(&1 + 1))
        _ -> Map.update!(acc, :warnings, &(&1 + 1))
      end
    end)
  end

  defp insert_machine_metrics(_build_id, _project_id, [], _now), do: :ok

  defp insert_machine_metrics(build_id, project_id, machine_metrics, now) do
    rows =
      machine_metrics
      |> Enum.filter(fn sample ->
        timestamp = number(sample, :timestamp)
        is_number(timestamp) and timestamp >= 0 and timestamp <= @max_timestamp
      end)
      |> Enum.map(fn sample ->
        %{
          build_run_id: nil,
          gradle_build_id: nil,
          mix_build_id: build_id,
          project_id: project_id,
          timestamp: number(sample, :timestamp) || 0.0,
          offset_ms: number(sample, :offset_ms),
          cpu_usage_percent: sample |> number(:cpu_usage_percent) |> percent(),
          memory_used_bytes: integer_value(sample, :memory_used_bytes) || 0,
          memory_total_bytes: integer_value(sample, :memory_total_bytes) || 0,
          network_bytes_in: integer_value(sample, :network_bytes_in) || 0,
          network_bytes_out: integer_value(sample, :network_bytes_out) || 0,
          disk_bytes_read: integer_value(sample, :disk_bytes_read) || 0,
          disk_bytes_written: integer_value(sample, :disk_bytes_written) || 0,
          inserted_at: now
        }
      end)

    BuildMachineMetric.Buffer.insert_all(rows)
    :ok
  end

  defp number(sample, key) do
    case Map.get(sample, key) || Map.get(sample, Atom.to_string(key)) do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp integer_value(sample, key) do
    case Map.get(sample, key) || Map.get(sample, Atom.to_string(key)) do
      value when is_integer(value) -> value |> max(0) |> min(@int64)
      _ -> nil
    end
  end

  defp percent(value) when is_number(value), do: value |> max(0) |> min(100) |> Kernel./(1)
  defp percent(_value), do: 0.0

  defp insert_compiled_files(_build_id, _project_id, [], _now), do: :ok

  defp insert_compiled_files(build_id, project_id, files, now) do
    rows =
      Enum.map(files, fn file ->
        waits = Enum.take(field(file, :waits) || [], @max_nested)

        dependencies =
          (field(file, :dependencies) || [])
          |> Enum.reject(&(string_field(&1, :path) == ""))
          |> Enum.take(@max_nested)

        %{
          id: UUIDv7.generate(),
          build_id: build_id,
          project_id: project_id,
          path: string_field(file, :path),
          start_offset_ms: integer_field(file, :start_offset_ms),
          compile_duration_ms: integer_field(file, :compile_duration_ms) || 0,
          wait_duration_ms: integer_field(file, :wait_duration_ms) || 0,
          modules: Enum.take(field(file, :modules) || [], @max_nested),
          dependency_paths: Enum.map(dependencies, &string_field(&1, :path)),
          dependency_kinds: Enum.map(dependencies, &dependency_kind/1),
          wait_durations_ms: Enum.map(waits, &(integer_field(&1, :duration_ms) || 0)),
          wait_start_offsets_ms: Enum.map(waits, &integer_field(&1, :start_offset_ms)),
          inserted_at: now
        }
      end)

    CompiledFile.Buffer.insert_all(rows)
    :ok
  end

  @step_categories ~w(type_check write compiler other)

  defp insert_steps(_build_id, _project_id, [], _now), do: :ok

  defp insert_steps(build_id, project_id, steps, now) do
    rows =
      Enum.map(steps, fn step ->
        category = string_field(step, :category)

        %{
          id: UUIDv7.generate(),
          build_id: build_id,
          project_id: project_id,
          category: if(category in @step_categories, do: category, else: "other"),
          title: string_field(step, :title),
          path: string_field(step, :path),
          start_offset_ms: integer_field(step, :start_offset_ms) || 0,
          duration_ms: integer_field(step, :duration_ms) || 0,
          inserted_at: now
        }
      end)

    Step.Buffer.insert_all(rows)
    :ok
  end

  defp dependency_kind(dependency) do
    case string_field(dependency, :kind) do
      kind when kind in ["compile", "export"] -> kind
      _ -> "runtime"
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp insert_diagnostics(_build_id, _project_id, [], _now), do: :ok

  defp insert_diagnostics(build_id, project_id, diagnostics, now) do
    rows =
      Enum.map(diagnostics, fn diagnostic ->
        %{
          id: UUIDv7.generate(),
          build_id: build_id,
          project_id: project_id,
          severity: diagnostic_severity(diagnostic),
          file: string_field(diagnostic, :file),
          module: string_field(diagnostic, :module),
          message: string_field(diagnostic, :message),
          line: integer_field(diagnostic, :line),
          column: integer_field(diagnostic, :column),
          compiler: string_field(diagnostic, :compiler),
          inserted_at: now
        }
      end)

    Diagnostic.Buffer.insert_all(rows)
    :ok
  end

  defp diagnostic_severity(diagnostic) do
    case string_field(diagnostic, :severity) do
      "error" -> "error"
      _ -> "warning"
    end
  end

  defp string_field(diagnostic, key) do
    value = Map.get(diagnostic, key) || Map.get(diagnostic, Atom.to_string(key))

    case value do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  # Every integer read this way lands in a UInt32 column, which would wrap a
  # larger value around rather than reject it.
  defp integer_field(diagnostic, key) do
    value = Map.get(diagnostic, key) || Map.get(diagnostic, Atom.to_string(key))

    case value do
      value when is_integer(value) and value >= 0 -> min(value, @uint32)
      _ -> nil
    end
  end

  defp to_naive_datetime(nil), do: nil

  defp to_naive_datetime(%DateTime{} = dt), do: dt |> DateTime.to_naive() |> to_naive_datetime()

  # The column stores microseconds, and a timestamp without a fractional part
  # ("2026-09-09T10:00:00Z") parses with second precision, so widen it.
  defp to_naive_datetime(%NaiveDateTime{microsecond: {microsecond, _precision}} = ndt),
    do: %{ndt | microsecond: {microsecond, 6}}

  defp to_naive_datetime(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> to_naive_datetime(dt)
      _ -> nil
    end
  end

  defp to_naive_datetime(_), do: nil
end
