defmodule LuftServer.ConversationImport do
  @moduledoc """
  Local whole-instance import of trusted plaintext Tuist snapshots. The caller
  supplies the independently verified SHA-256 and an exact upstream account
  ID/handle map. Never accepts old delegation or makes a session runnable.
  No Tuist Repo or conversation schemas are linked into this application.
  """

  alias LuftServer.Agents.SessionStore
  alias LuftServer.Repo
  alias LuftServer.Threads.EncryptedBinary

  @tables ~w(thread_runners threads thread_messages thread_participants thread_ship_approvals thread_runs thread_tool_calls thread_runner_requests thread_inboxes halls hall_members hall_messages agent_sessions)

  defmodule ReadbackBucket do
    @moduledoc false
    def get(objects, key), do: objects |> Map.get(key, :not_found) |> found()
    defp found(:not_found), do: :not_found
    defp found(body), do: {:ok, body}

    def list(objects, prefix, after_key) do
      {:ok,
       objects
       |> Map.keys()
       |> Enum.filter(
         &(String.starts_with?(&1, prefix) and (is_nil(after_key) or &1 > after_key))
       )
       |> Enum.sort()}
    end
  end

  def import(binary, opts) when is_binary(binary) do
    with true <- Keyword.get(opts, :maintenance) == true,
         true <-
           Base.encode16(:crypto.hash(:sha256, binary), case: :lower) ==
             Keyword.fetch!(opts, :sha256),
         %{
           "format" => "tuist-luft-conversations/1",
           "accounts" => accounts,
           "tables" => tables,
           "objects" => objects
         } <- :erlang.binary_to_term(binary, [:safe]),
         true <- Enum.sort(Map.keys(tables)) == Enum.sort(@tables),
         true <- accounts |> Map.new() |> Map.equal?(Keyword.fetch!(opts, :accounts)) do
      Repo.transaction(
        fn ->
          destinations =
            Enum.map(@tables, &destination/1) ++ ["agent_objects", "thread_runner_credentials"]

          Repo.query!(
            "LOCK TABLE " <> Enum.join(destinations, ", ") <> " IN ACCESS EXCLUSIVE MODE",
            [],
            log: false
          )

          Enum.each(destinations, fn table ->
            %{rows: [[empty]]} =
              Repo.query!("SELECT NOT EXISTS (SELECT 1 FROM " <> table <> ")", [], log: false)

            empty or Repo.rollback(:destination_not_empty)
          end)

          referenced_accounts =
            for rows <- Map.values(tables),
                row <- rows,
                id = row["account_id"],
                not is_nil(id),
                uniq: true,
                do: id

          if Enum.sort(referenced_accounts) != Enum.sort(Map.keys(Map.new(accounts))),
            do: Repo.rollback(:account_mapping_mismatch)

          for table <- @tables, row <- Map.fetch!(tables, table) do
            insert(destination(table), transform(table, row))
          end

          {_, store} = SessionStore.store("thread", "offline-import", 0)
          encrypt = Keyword.fetch!(store, :encrypt)

          Enum.each(objects, fn {key, body} ->
            true = String.starts_with?(key, "agents/thread/")
            # Match Condukt's trusted journal decoder: tool error atoms may
            # not yet exist in this VM. The operator must authenticate the file.
            _ = :erlang.binary_to_term(body)
            # Use this transaction's connection; never an external bucket or task.
            insert("agent_objects", %{"key" => key, "body" => encrypt.(body)})
          end)

          # Condukt reads segments in Task.async_stream. Those tasks cannot see
          # this transaction and would block behind our table locks. Read back
          # ciphertext on this connection, then validate through an immutable
          # bucket so no validation task opens another database connection.
          %{rows: stored_objects} =
            Repo.query!("SELECT key, body FROM agent_objects", [], log: false)

          readback = Map.new(stored_objects, fn [key, body] -> {key, body} end)

          objects
          |> Map.keys()
          |> Enum.map(&(&1 |> String.split("/") |> Enum.at(2)))
          |> Enum.uniq()
          |> Enum.each(&validate_readback!(&1, readback))

          %{
            rows: Map.new(tables, fn {table, rows} -> {destination(table), length(rows)} end),
            objects: map_size(objects)
          }
        end,
        timeout: :infinity
      )
    else
      _ -> {:error, :invalid_snapshot_or_preconditions}
    end
  rescue
    _ -> {:error, :invalid_snapshot_or_conflict}
  end

  defp validate_readback!(id, readback) do
    {module, config} = SessionStore.store("thread", id, 0)
    # No epoch means read-only: an epoch would create a fence object.
    config =
      config
      |> Keyword.delete(:epoch)
      |> Keyword.put(:bucket, {ReadbackBucket, readback})

    case module.load(config) do
      :not_found -> :ok
      {:ok, _} -> :ok
      _ -> Repo.rollback(:corrupt_session_snapshot)
    end

    {:ok, _} = module.load_journal(config)
  end

  defp destination("halls"), do: "lounges"
  defp destination("hall_members"), do: "lounge_members"
  defp destination("hall_messages"), do: "lounge_messages"
  defp destination(table), do: table

  defp transform("threads", row), do: Map.put(row, "owner_session_id", nil)
  defp transform("thread_messages", row), do: Map.put(row, "author_session_id", nil)

  defp transform("thread_runners", row) do
    row
    |> Map.put("token_hash", :crypto.strong_rand_bytes(32))
    |> Map.put("revoked_at", DateTime.utc_now())
  end

  defp transform("agent_sessions", row) do
    true = row["kind"] == "thread"

    row
    |> Map.put("wanted", false)
    |> Map.put("wanted_at", nil)
    |> Map.put("host", nil)
    |> Map.put("lease_expires_at", nil)
  end

  defp transform("thread_runner_requests", row) do
    if row["status"] in ["pending", "claimed"], do: Map.put(row, "status", "cancelled"), else: row
  end

  defp transform("halls", row) do
    if row["kind"] == "hall", do: Map.put(row, "kind", "lounge"), else: row
  end

  defp transform(table, row) when table in ["hall_members", "hall_messages"] do
    {id, row} = Map.pop!(row, "hall_id")
    Map.put(row, "lounge_id", id)
  end

  defp transform("thread_runs", row), do: encrypt_field(row, "checkpoint")
  defp transform("thread_tool_calls", row), do: encrypt_field(row, "result")
  defp transform(_, row), do: row

  defp encrypt_field(row, field) do
    Map.update!(row, field, fn
      nil ->
        nil

      plaintext ->
        {:ok, ciphertext} = EncryptedBinary.dump(plaintext)
        ciphertext
    end)
  end

  defp insert(table, row) do
    columns = row |> Map.keys() |> Enum.sort()
    true = Enum.all?(columns, &Regex.match?(~r/\A[a-z_]+\z/, &1))
    placeholders = Enum.map_join(1..length(columns), ",", &"$#{&1}")

    Repo.query!(
      "INSERT INTO " <>
        table <> " (" <> Enum.join(columns, ",") <> ") VALUES (" <> placeholders <> ")",
      Enum.map(columns, &Map.fetch!(row, &1)),
      log: false
    )
  end
end
