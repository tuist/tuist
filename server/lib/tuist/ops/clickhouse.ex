defmodule Tuist.Ops.ClickHouse do
  @moduledoc """
  Bounded, read-only ClickHouse inspection for the internal Atlas workload.

  Callers can run analytical queries and discover tables in the application
  database. Every query is forced into read-only mode and receives stricter
  execution, scan, memory, thread, and result limits than regular application
  reads.
  """

  alias Tuist.ClickHouseRepo

  @max_rows 200
  @max_execution_time_seconds 10
  @request_timeout_milliseconds 15_000
  @max_memory_usage_bytes 1024 * 1024 * 1024
  @max_rows_to_read 100_000_000
  @max_bytes_to_read 5_000_000_000
  @max_threads 2

  @doc """
  Runs a bounded read-only query.

  Named ClickHouse parameters use placeholders such as
  `{project_ids:Array(Int64)}` and are passed through `opts[:params]`.
  """
  def execute(statement, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @max_rows) |> clamp_limit()
    params = Keyword.get(opts, :params, %{})

    with :ok <- validate_params(params),
         {:ok, command, normalized_statement} <- validate_statement(statement),
         result_limit = limit + 1,
         {:ok, payload} <-
           run_query(bound_statement(command, normalized_statement, result_limit), params, result_limit) do
      {:ok, build_result(payload, limit)}
    end
  end

  @doc "Lists tables in the configured application database."
  def list_table_overviews do
    statement = """
    SELECT
      database,
      name,
      engine,
      coalesce(total_rows, 0) AS estimated_rows,
      coalesce(total_bytes, 0) AS size_bytes,
      formatReadableSize(coalesce(total_bytes, 0)) AS size
    FROM system.tables
    WHERE database = currentDatabase()
      AND is_temporary = 0
    ORDER BY size_bytes DESC, name
    """

    with {:ok, result} <- execute(statement) do
      {:ok, result.rows}
    end
  end

  @doc "Lists column metadata for a table in the configured application database."
  def list_table_columns(database, name) do
    statement = """
    SELECT
      name,
      type,
      default_kind,
      default_expression,
      comment,
      is_in_primary_key,
      is_in_sorting_key
    FROM system.columns
    WHERE database = {database:String}
      AND database = currentDatabase()
      AND table = {table:String}
    ORDER BY position
    """

    with {:ok, result} <-
           execute(statement,
             params: %{
               "database" => database,
               "table" => name
             }
           ) do
      {:ok, result.rows}
    end
  end

  @doc "Whether a table belongs to the configured application database."
  def app_table_exists?(database, name) do
    statement = """
    SELECT count() AS matching_tables
    FROM system.tables
    WHERE database = {database:String}
      AND database = currentDatabase()
      AND name = {table:String}
      AND is_temporary = 0
    """

    with {:ok, %{rows: [%{"matching_tables" => matching_tables}]}} <-
           execute(statement,
             params: %{
               "database" => database,
               "table" => name
             },
             limit: 1
           ) do
      {:ok, matching_tables > 0}
    end
  end

  defp validate_params(params) when is_map(params), do: :ok
  defp validate_params(_params), do: {:error, "Query parameters must be an object"}

  defp validate_statement(statement) when is_binary(statement) do
    normalized_statement = statement |> String.trim() |> String.trim_trailing(";") |> String.trim()

    cond do
      normalized_statement == "" ->
        {:error, "Empty query"}

      Regex.match?(~r/^select\b/i, normalized_statement) ->
        {:ok, :select, normalized_statement}

      Regex.match?(~r/^with\b/i, normalized_statement) ->
        {:ok, :select, normalized_statement}

      Regex.match?(~r/^explain\b/i, normalized_statement) ->
        {:ok, :metadata, normalized_statement}

      Regex.match?(~r/^show\b/i, normalized_statement) ->
        {:ok, :metadata, normalized_statement}

      Regex.match?(~r/^describe\b/i, normalized_statement) ->
        {:ok, :metadata, normalized_statement}

      true ->
        {:error, "Only SELECT, WITH, EXPLAIN, SHOW, and DESCRIBE statements are allowed"}
    end
  end

  defp validate_statement(_statement), do: {:error, "Query must be a string"}

  # An outer limit bounds the response without trying to parse or rewrite the
  # caller's own LIMIT, UNION, SETTINGS, or nested query clauses.
  defp bound_statement(:select, statement, result_limit) do
    """
    SELECT *
    FROM (
      #{statement}
    )
    LIMIT #{result_limit}
    """
  end

  defp bound_statement(:metadata, statement, _result_limit), do: statement

  defp run_query(statement, params, result_limit) do
    settings = [
      readonly: 1,
      max_execution_time: @max_execution_time_seconds,
      max_memory_usage: @max_memory_usage_bytes,
      max_rows_to_read: @max_rows_to_read,
      max_bytes_to_read: @max_bytes_to_read,
      max_threads: @max_threads,
      max_result_rows: result_limit,
      max_block_size: result_limit,
      result_overflow_mode: "break",
      output_format_json_quote_64bit_integers: 0
    ]

    case ClickHouseRepo.query(statement, params,
           settings: settings,
           timeout: @request_timeout_milliseconds,
           format: "JSONCompact",
           decode: false
         ) do
      {:ok, %{data: data}} ->
        decode_result(data)

      {:error, %DBConnection.ConnectionError{}} ->
        {:error, :unavailable}

      {:error, %Mint.TransportError{}} ->
        {:error, :unavailable}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  rescue
    _error in [DBConnection.ConnectionError, Mint.TransportError] ->
      {:error, :unavailable}
  end

  defp decode_result(data) do
    case data |> IO.iodata_to_binary() |> JSON.decode() do
      {:ok, %{"meta" => metadata, "data" => rows}} when is_list(metadata) and is_list(rows) ->
        columns = Enum.map(metadata, &Map.fetch!(&1, "name"))
        {:ok, %{columns: columns, rows: rows}}

      {:ok, _payload} ->
        {:error, "ClickHouse returned an unexpected response"}

      {:error, _reason} ->
        {:error, "ClickHouse returned a response that could not be decoded"}
    end
  end

  defp build_result(%{columns: columns, rows: rows}, limit) do
    {kept_rows, truncated?} =
      if length(rows) > limit do
        {Enum.take(rows, limit), true}
      else
        {rows, false}
      end

    %{
      columns: columns,
      rows: Enum.map(kept_rows, &Map.new(Enum.zip(columns, &1))),
      num_rows: length(kept_rows),
      truncated?: truncated?
    }
  end

  defp clamp_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, @max_rows)
  defp clamp_limit(_limit), do: @max_rows
end
