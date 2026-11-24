defmodule Tuist.Vault.Reencryption do
  @moduledoc """
  Moves every stored `Tuist.Vault.Binary` value to the vault's current key, so
  a retired key can be dropped. Run it through `Tuist.Release.reencrypt_vault/2`.

  The fields are found at run time from the application's Ecto schemas, so a
  field added later is covered without listing it here. Ciphertexts stored
  inside JSON, where a schema cannot declare them, are listed in
  `embedded_tables/0`: the Slack webhook URLs of automation actions
  (`Tuist.Slack.encrypt_webhook_url/1`). Any new one has to be added there. Each table is walked
  in primary key order, a bounded batch at a time, and a value already under
  the current key is left alone, so an interrupted run is resumed by running it
  again. Each value is rewritten only if it still holds what was read, so a
  concurrent write by the application is never overwritten.
  """
  alias Tuist.Environment
  alias Tuist.Repo

  require Logger

  @default_batch_size 500

  @doc """
  The Postgres tables that hold `Tuist.Vault.Binary` fields, with their
  primary key and encrypted column names.
  """
  def tables do
    {:ok, modules} = :application.get_key(:tuist, :modules)

    modules
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__schema__, 1)))
    |> Enum.flat_map(fn schema ->
      columns =
        for field <- schema.__schema__(:fields),
            schema.__schema__(:type, field) == Tuist.Vault.Binary,
            do: to_string(schema.__schema__(:field_source, field))

      # Embedded schemas have no source: their values live inside another row.
      if columns == [] or is_nil(schema.__schema__(:source)) do
        []
      else
        primary_key = Enum.map(schema.__schema__(:primary_key), &to_string(schema.__schema__(:field_source, &1)))

        [
          %{
            prefix: schema.__schema__(:prefix),
            table: schema.__schema__(:source),
            primary_key: primary_key,
            columns: columns
          }
        ]
      end
    end)
    |> Enum.group_by(&{&1.prefix, &1.table})
    |> Enum.map(fn {_source, [table | _] = tables} ->
      %{table | columns: tables |> Enum.flat_map(& &1.columns) |> Enum.uniq() |> Enum.sort()}
    end)
    |> Enum.sort_by(&{&1.prefix, &1.table})
  end

  @doc """
  Tables holding `Tuist.Vault` ciphertexts inside JSON: lists of action maps
  whose `webhook_url_encrypted` is a base64 ciphertext.
  """
  def embedded_tables do
    [
      %{
        prefix: nil,
        table: "automation_alerts",
        primary_key: ["id"],
        columns: ["recovery_actions", "trigger_actions"],
        kind: :webhook_actions
      }
    ]
  end

  @doc """
  Re-encrypts every value not under the current key, which must be `key_id`.
  Returns the counts per `table.column`: `reencrypted` values, values a
  concurrent write `changed` first, and values that `failed` to decrypt.

  Options: `:batch_size` (default #{@default_batch_size}).
  """
  def run(key_id, opts \\ []) do
    {cipher, cipher_opts} = Tuist.Vault.current_cipher()
    current_tag = "AES.GCM.#{key_id}"

    if cipher_opts[:tag] != current_tag do
      raise "This node encrypts with #{cipher_opts[:tag]}, not #{current_tag}: make #{key_id} the current key " <>
              "(TUIST_SECRET_KEY_ENCRYPTION_CURRENT_KEY) on every node before re-encrypting"
    end

    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    current? = &current_ciphertext?(&1, cipher, cipher_opts)

    Map.new(
      for table <- tables() ++ embedded_tables(), {column, counts} <- reencrypt_table(table, current?, batch_size) do
        {"#{table.table}.#{column}", counts}
      end
    )
  end

  defp reencrypt_table(%{primary_key: []} = table, _current?, _batch_size) do
    Logger.error("Cannot re-encrypt #{table.table}: it has no primary key to walk it by")
    Map.new(table.columns, &{&1, %{reencrypted: 0, changed: 0, failed: :no_primary_key}})
  end

  defp reencrypt_table(table, current?, batch_size) do
    initial = Map.new(table.columns, &{&1, %{reencrypted: 0, changed: 0, failed: 0}})
    counts = reencrypt_batches(table, current?, batch_size, nil, initial)

    for {column, %{reencrypted: reencrypted, changed: changed, failed: failed}} <- counts do
      Logger.info(
        "Re-encrypted #{table.table}.#{column}: #{reencrypted} values, #{changed} changed concurrently, #{failed} failed"
      )
    end

    counts
  end

  defp reencrypt_batches(table, current?, batch_size, last_key, counts) do
    rows = select_batch(table, batch_size, last_key)
    key_size = length(table.primary_key)

    counts =
      Enum.reduce(rows, counts, fn row, counts ->
        {key, values} = Enum.split(row, key_size)

        table.columns
        |> Enum.zip(values)
        |> Enum.reject(fn {_column, value} -> is_nil(value) end)
        |> Enum.reduce(counts, fn {column, value}, counts ->
          delta = reencrypt_column(Map.get(table, :kind, :binary), table, column, key, value, current?)
          Map.update!(counts, column, &Map.merge(&1, delta, fn _outcome, a, b -> a + b end))
        end)
      end)

    if length(rows) < batch_size do
      counts
    else
      reencrypt_batches(table, current?, batch_size, rows |> List.last() |> Enum.take(key_size), counts)
    end
  end

  defp select_batch(table, batch_size, last_key) do
    key = Enum.map_join(table.primary_key, ", ", &quote_identifier/1)
    columns = Enum.map_join(table.primary_key ++ table.columns, ", ", &quote_identifier/1)

    {where, params} =
      case last_key do
        nil -> {"", []}
        last_key -> {"WHERE (#{key}) > (#{placeholders(1, length(last_key))})", last_key}
      end

    sql = "SELECT #{columns} FROM #{qualified_table(table)} #{where} ORDER BY #{key} LIMIT #{batch_size}"
    Repo.query!(sql, params, log: false).rows
  end

  defp reencrypt_column(:binary, table, column, key, value, current?) do
    with false <- current?.(value),
         {:ok, plaintext} <- decrypt(value) do
      %{compare_and_set(table, column, key, value, Tuist.Vault.encrypt!(plaintext)) => 1}
    else
      true ->
        %{}

      :error ->
        log_failure(table, column, key)
        %{failed: 1}
    end
  end

  defp reencrypt_column(:webhook_actions, table, column, key, actions, current?) do
    {actions_after, outcomes} = Enum.map_reduce(actions, [], &reencrypt_action(&1, &2, current?))
    rewritten = Enum.count(outcomes, &(&1 == :reencrypted))
    failed = Enum.count(outcomes, &(&1 == :failed))
    if failed > 0, do: log_failure(table, column, key)

    if rewritten > 0 do
      %{compare_and_set(table, column, key, actions, actions_after) => rewritten, failed: failed}
    else
      %{failed: failed}
    end
  end

  defp reencrypt_action(%{"webhook_url_encrypted" => encoded} = action, outcomes, current?)
       when is_binary(encoded) and encoded != "" do
    with {:ok, ciphertext} <- Base.decode64(encoded),
         false <- current?.(ciphertext),
         {:ok, plaintext} <- decrypt(ciphertext) do
      encoded = Base.encode64(Tuist.Vault.encrypt!(plaintext))
      {Map.put(action, "webhook_url_encrypted", encoded), [:reencrypted | outcomes]}
    else
      true -> {action, outcomes}
      _ -> {action, [:failed | outcomes]}
    end
  end

  defp reencrypt_action(action, outcomes, _current?), do: {action, outcomes}

  # Writes the column only if it still holds what was read, so a concurrent
  # write by the application is never overwritten.
  defp compare_and_set(table, column, key, old, new) do
    conditions =
      table.primary_key
      |> Enum.with_index(3)
      |> Enum.map_join(" AND ", fn {key_column, index} -> "#{quote_identifier(key_column)} = $#{index}" end)

    sql =
      "UPDATE #{qualified_table(table)} SET #{quote_identifier(column)} = $1 " <>
        "WHERE #{conditions} AND #{quote_identifier(column)} = $2"

    case Repo.query!(sql, [new, old | key], log: false) do
      %{num_rows: 1} -> :reencrypted
      %{num_rows: 0} -> :changed
    end
  end

  # The row's key only: the value is a secret.
  defp log_failure(table, column, key) do
    Logger.error("Cannot decrypt #{table.table}.#{column} of row #{inspect(key)} with any configured key")
  end

  defp decrypt(value) do
    # Cloak answers `{:ok, :error}` when the tag names a configured key but the
    # value does not authenticate under it (another key, or tampered bytes).
    case Tuist.Vault.decrypt(value) do
      {:ok, plaintext} when is_binary(plaintext) -> {:ok, plaintext}
      _ -> :error
    end
  rescue
    # Cloak's tag decoding raises on a value too short to hold a tag.
    _ -> :error
  end

  defp current_ciphertext?(value, cipher, opts) do
    cipher.can_decrypt?(value, opts)
  rescue
    _ -> false
  end

  defp placeholders(from, count), do: Enum.map_join(from..(from + count - 1)//1, ", ", &"$#{&1}")

  defp qualified_table(%{prefix: nil, table: table}), do: quote_identifier(table)
  defp qualified_table(%{prefix: prefix, table: table}), do: "#{quote_identifier(prefix)}.#{quote_identifier(table)}"

  defp quote_identifier(identifier), do: Environment.quote_postgres_identifier(to_string(identifier))
end
