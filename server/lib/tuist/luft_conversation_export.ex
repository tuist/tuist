defmodule Tuist.LuftConversationExport do
  @moduledoc """
  Offline, whole-instance conversation snapshot. Requires externally quiesced
  writers, including object-store writers. Does not start conversation code or
  mutate source data. Keep this module, Repo, Vault and the bucket adapter when
  retiring the runtime conversation contexts. The returned binary is PLAINTEXT.
  """

  alias Condukt.SessionStore.ObjectStore

  @tables ~w(thread_runners threads thread_messages thread_participants thread_ship_approvals thread_runs thread_tool_calls thread_runner_requests thread_inboxes halls hall_members hall_messages agent_sessions)

  defmodule LegacyS3Bucket do
    @moduledoc """
    Read-only access to retained Tuist journal objects. Keep this adapter with
    the exporter when removing the runtime agent modules. It has no write or
    delete operations; retirement requires separate operator approval.
    """

    def get(_config, key) do
      case Tuist.Environment.s3_bucket_name() |> ExAws.S3.get_object(key) |> ExAws.request() do
        {:ok, %{body: body}} -> {:ok, body}
        {:error, {:http_error, 404, _}} -> :not_found
        {:error, {:http_error, status, _}} -> {:error, {:http, status}}
        {:error, _} -> {:error, :get_failed}
      end
    end

    def list(_config, prefix, start_after) do
      opts = if start_after, do: [prefix: prefix, start_after: start_after], else: [prefix: prefix]

      Tuist.Environment.s3_bucket_name()
      |> ExAws.S3.list_objects_v2(opts)
      |> ExAws.stream!()
      |> Enum.map(& &1.key)
      |> then(&{:ok, &1})
    rescue
      _ -> {:error, :list_failed}
    end
  end

  defmodule PlaintextBucket do
    @moduledoc false
    def get(objects, key), do: Map.fetch(objects, key)

    def list(objects, prefix, after_key) do
      {:ok,
       objects
       |> Map.keys()
       |> Enum.filter(&(String.starts_with?(&1, prefix) and (is_nil(after_key) or &1 > after_key)))
       |> Enum.sort()}
    end
  end

  def export(opts) do
    if Keyword.get(opts, :quiesced) == true do
      repo = Keyword.get(opts, :repo, Tuist.Repo)

      bucket =
        Keyword.get_lazy(opts, :bucket, fn ->
          :tuist
          |> Application.get_env(__MODULE__, [])
          |> Keyword.get(:bucket, {LegacyS3Bucket, []})
        end)

      decrypt = Keyword.get(opts, :decrypt, &Tuist.Vault.decrypt!/1)

      repo.transaction(
        fn ->
          repo.query!("LOCK TABLE " <> Enum.join(@tables, ", ") <> " IN SHARE MODE", [], log: false)

          tables = Map.new(@tables, &{&1, rows(repo, &1)})
          sessions = Enum.filter(tables["agent_sessions"], &(&1["kind"] == "thread"))

          if Enum.any?(sessions, &(&1["host"] != nil or &1["lease_expires_at"] != nil)) do
            repo.rollback(:source_has_leases)
          end

          tables =
            tables
            |> Map.put("agent_sessions", sessions)
            |> Map.update!("thread_runs", &decrypt_rows(&1, "checkpoint", decrypt))
            |> Map.update!("thread_tool_calls", &decrypt_rows(&1, "result", decrypt))
            # Old runner secrets are not needed even in the offline archive.
            |> Map.update!("thread_runners", fn rows -> Enum.map(rows, &Map.put(&1, "token_hash", nil)) end)

          {module, config} = bucket
          {:ok, keys} = module.list(config, "agents/thread/", nil)

          objects =
            Map.new(keys, fn key ->
              true = String.starts_with?(key, "agents/thread/")
              {:ok, ciphertext} = module.get(config, key)
              plaintext = decrypt.(ciphertext)
              # Journals may contain tool error atoms unknown to this VM, as in
              # Condukt's reader. Only decode trusted, authenticated source data.
              _ = :erlang.binary_to_term(plaintext)
              {key, plaintext}
            end)

          objects
          |> Map.keys()
          |> Enum.map(&(&1 |> String.split("/") |> Enum.at(2)))
          |> Enum.uniq()
          |> Enum.each(fn id ->
            read_opts = [bucket: {PlaintextBucket, objects}, prefix: "agents/thread", key: id]
            validate_snapshot(repo, ObjectStore.load(read_opts))
            {:ok, _} = ObjectStore.load_journal(read_opts)
          end)

          account_ids =
            tables
            |> Map.values()
            |> List.flatten()
            |> Enum.map(& &1["account_id"])
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
            |> Enum.sort()

          accounts =
            Enum.map(account_ids, fn id ->
              %{rows: [[handle]]} = repo.query!("SELECT name FROM accounts WHERE id = $1", [id], log: false)
              {id, handle}
            end)

          binary =
            :erlang.term_to_binary(%{
              "format" => "tuist-luft-conversations/1",
              "accounts" => accounts,
              "tables" => tables,
              "objects" => objects
            })

          %{binary: binary, sha256: Base.encode16(:crypto.hash(:sha256, binary), case: :lower)}
        end,
        timeout: :infinity
      )
    else
      {:error, :source_not_quiesced}
    end
  rescue
    _ -> {:error, :export_failed}
  end

  defp validate_snapshot(_, :not_found), do: :ok
  defp validate_snapshot(_, {:ok, _}), do: :ok
  defp validate_snapshot(repo, _), do: repo.rollback(:corrupt_session_snapshot)

  defp rows(repo, table) do
    where = if table == "agent_sessions", do: " WHERE kind = 'thread'", else: ""
    %{columns: columns, rows: rows} = repo.query!("SELECT * FROM " <> table <> where, [], log: false)
    Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
  end

  defp decrypt_rows(rows, field, decrypt) do
    Enum.map(rows, fn row ->
      Map.update!(row, field, fn
        nil -> nil
        value -> decrypt.(value)
      end)
    end)
  end
end
