defmodule Tuist.Ops.ClickHouse do
  @moduledoc """
  Bounded, read-only ClickHouse inspection for the internal Atlas workload.

  Callers can run analytical queries and discover tables in the application
  database. Every query is forced into read-only mode and receives stricter
  execution, scan, memory, thread, and result limits than regular application
  reads.
  """

  alias Tuist.OpsClickHouseRepo

  require Logger

  @max_rows 200
  @max_execution_time_seconds 10
  @request_timeout_milliseconds 15_000
  @max_memory_usage_bytes 1024 * 1024 * 1024
  @max_rows_to_read 100_000_000
  @max_bytes_to_read 5_000_000_000
  @max_result_bytes 5 * 1024 * 1024
  @max_threads 2
  @prohibited_table_functions ~w(
    azureblobstorage
    azureblobstoragecluster
    azurequeue
    cluster
    clusterallreplicas
    deltalake
    deltalakecluster
    dictionary
    executable
    executablepool
    file
    filecluster
    gcs
    gcscluster
    hdfs
    hdfscluster
    hudi
    iceberg
    icebergcluster
    jdbc
    kafka
    merge
    mongodb
    mysql
    null
    odbc
    postgresql
    redis
    remote
    remotesecure
    s3
    s3cluster
    sqlite
    url
    urlcluster
    view
  )
  @prohibited_table_function_patterns Enum.map(
                                        @prohibited_table_functions,
                                        &Regex.compile!("\\b#{&1}\\s*\\(")
                                      )
  @string_literal_pattern ~r/'(?:''|\\.|[^'\\])*'/s
  @restricted_database_pattern ~r/\b(?:information_schema|system)\s*\./
  @unsupported_output_clause_pattern ~r/\b(?:format\s+[a-z0-9_]+|into\s+outfile\b[^;]*)\s*$/i

  @doc """
  Runs a bounded read-only query.

  Named ClickHouse parameters use placeholders such as
  `{project_ids:Array(Int64)}` and are passed through `opts[:params]`.
  """
  def execute(statement, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @max_rows) |> clamp_limit()
    params = Keyword.get(opts, :params, %{})
    allow_system_tables? = Keyword.get(opts, :allow_system_tables, false)

    with :ok <- validate_params(params),
         {:ok, normalized_statement} <- validate_statement(statement, allow_system_tables?),
         result_limit = limit + 1,
         {:ok, payload} <-
           run_query(bound_statement(normalized_statement, result_limit), params, result_limit) do
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

    with {:ok, result} <- execute(statement, allow_system_tables: true) do
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
             },
             allow_system_tables: true
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
             allow_system_tables: true,
             limit: 1
           ) do
      {:ok, matching_tables > 0}
    end
  end

  defp validate_params(params) when is_map(params), do: :ok
  defp validate_params(_params), do: {:error, "Query parameters must be an object"}

  defp validate_statement(statement, allow_system_tables?) when is_binary(statement) do
    normalized_statement = statement |> String.trim() |> String.trim_trailing(";") |> String.trim()
    validation_statement = statement_for_validation(normalized_statement)

    cond do
      normalized_statement == "" ->
        {:error, "Empty query"}

      prohibited_table_function?(validation_statement) ->
        {:error, "External and cluster table functions are not allowed"}

      not allow_system_tables? and Regex.match?(@restricted_database_pattern, validation_statement) ->
        {:error, "System metadata tables are not available through the query endpoint"}

      Regex.match?(@unsupported_output_clause_pattern, validation_statement) ->
        {:error, "FORMAT and INTO OUTFILE clauses are not supported"}

      Regex.match?(~r/^select\b/i, normalized_statement) ->
        {:ok, normalized_statement}

      Regex.match?(~r/^with\b/i, normalized_statement) ->
        {:ok, normalized_statement}

      true ->
        {:error, "Only SELECT and WITH statements are allowed"}
    end
  end

  defp validate_statement(_statement, _allow_system_tables?), do: {:error, "Query must be a string"}

  # An outer limit bounds the response without trying to parse or rewrite the
  # caller's own LIMIT, UNION, SETTINGS, or nested query clauses.
  defp bound_statement(statement, result_limit) do
    """
    SELECT *
    FROM (
      #{statement}
    )
    LIMIT #{result_limit}
    """
  end

  defp run_query(statement, params, result_limit) do
    settings = [
      max_execution_time: @max_execution_time_seconds,
      max_memory_usage: @max_memory_usage_bytes,
      max_rows_to_read: @max_rows_to_read,
      max_bytes_to_read: @max_bytes_to_read,
      max_threads: @max_threads,
      max_result_rows: result_limit,
      max_result_bytes: @max_result_bytes,
      max_block_size: result_limit,
      result_overflow_mode: "throw",
      output_format_json_quote_64bit_integers: 0
    ]

    if Process.whereis(OpsClickHouseRepo) do
      do_run_query(statement, params, settings)
    else
      {:error, :unavailable}
    end
  end

  defp do_run_query(statement, params, settings) do
    case OpsClickHouseRepo.query(statement, params,
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
        log_query_failure(error)
        {:error, :query_failed}
    end
  rescue
    _error in [DBConnection.ConnectionError, Mint.TransportError] ->
      {:error, :unavailable}

    error ->
      log_query_failure(error)
      {:error, :query_failed}
  catch
    :exit, reason ->
      Logger.warning("Internal ClickHouse query process exited: #{inspect(reason)}")
      {:error, :unavailable}
  end

  defp decode_result(data) do
    if IO.iodata_length(data) > @max_result_bytes do
      {:error, :result_too_large}
    else
      decode_bounded_result(data)
    end
  end

  defp decode_bounded_result(data) do
    case data |> IO.iodata_to_binary() |> JSON.decode() do
      {:ok, %{"meta" => metadata, "data" => rows}} when is_list(metadata) and is_list(rows) ->
        columns = Enum.map(metadata, &Map.fetch!(&1, "name"))
        {:ok, %{columns: columns, rows: rows}}

      {:ok, _payload} ->
        Logger.warning("Internal ClickHouse query returned an unexpected response")
        {:error, :query_failed}

      {:error, reason} ->
        Logger.warning("Internal ClickHouse response decoding failed: #{inspect(reason)}")
        {:error, :query_failed}
    end
  end

  defp log_query_failure(error) do
    Logger.warning("Internal ClickHouse query failed: #{inspect(error)}")
  end

  defp statement_for_validation(statement) do
    statement
    |> String.replace(@string_literal_pattern, "''")
    |> String.replace(~r/--[^\n]*(?:\n|$)/, "")
    |> String.replace(~r/\/\*.*?\*\//s, "")
    |> String.replace(["`", "\""], "")
    |> String.downcase()
  end

  defp prohibited_table_function?(statement) do
    Enum.any?(@prohibited_table_function_patterns, &Regex.match?(&1, statement))
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
