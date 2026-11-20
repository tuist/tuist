defmodule Tuist.LuftConversationExportTest do
  # Source SHARE locks must not overlap other tests' writes.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.LuftConversationExport
  alias Tuist.LuftConversationExport.LegacyS3Bucket

  defmodule EmptyBucket do
    @moduledoc false
    def list(_, "agents/thread/", nil), do: {:ok, []}
  end

  defmodule MemoryBucket do
    @moduledoc false
    def list(objects, "agents/thread/", nil), do: {:ok, Map.keys(objects)}
    def get(objects, key), do: Map.fetch(objects, key)
  end

  test "requires explicit source quiescence" do
    assert {:error, :source_not_quiesced} = LuftConversationExport.export([])
  end

  test "the default retained S3 adapter decrypts and reads back journals without runtime agent modules" do
    key = "agents/thread/history/wal/00000000000000000001"
    journal = :erlang.term_to_binary({:records, ["retained private journal"]})
    ciphertext = Tuist.Vault.encrypt!(journal)
    stub(Tuist.Environment, :s3_bucket_name, fn -> "retained-bucket" end)

    expect(ExAws.S3, :list_objects_v2, fn "retained-bucket", [prefix: "agents/thread/"] ->
      :legacy_list_operation
    end)

    expect(ExAws, :stream!, fn :legacy_list_operation -> [%{key: key}] end)

    expect(ExAws.S3, :get_object, fn "retained-bucket", ^key ->
      :legacy_get_operation
    end)

    expect(ExAws, :request, fn :legacy_get_operation -> {:ok, %{body: ciphertext}} end)

    assert {:ok, %{binary: binary}} = LuftConversationExport.export(quiesced: true)
    data = :erlang.binary_to_term(binary, [:safe])
    assert data["objects"] == %{key => journal}

    assert {:ok, ["retained private journal"]} =
             Condukt.SessionStore.ObjectStore.load_journal(
               bucket: {LuftConversationExport.PlaintextBucket, data["objects"]},
               prefix: "agents/thread",
               key: "history"
             )

    refute function_exported?(LegacyS3Bucket, :create, 3)
    refute function_exported?(LegacyS3Bucket, :delete, 2)
  end

  test "the retained S3 adapter preserves listing cursors and sanitizes failed reads" do
    stub(Tuist.Environment, :s3_bucket_name, fn -> "retained-bucket" end)

    expect(ExAws.S3, :list_objects_v2, fn "retained-bucket", [prefix: "agents/thread/", start_after: "previous"] ->
      :legacy_list_operation
    end)

    expect(ExAws, :stream!, fn :legacy_list_operation -> [] end)
    assert {:ok, []} = LegacyS3Bucket.list([], "agents/thread/", "previous")

    expect(ExAws.S3, :get_object, 2, fn "retained-bucket", "missing" -> :legacy_get_operation end)
    expect(ExAws, :request, fn :legacy_get_operation -> {:error, {:http_error, 404, "private response"}} end)
    assert :not_found = LegacyS3Bucket.get([], "missing")
    expect(ExAws, :request, fn :legacy_get_operation -> {:error, {:http_error, 403, "private response"}} end)
    assert {:error, {:http, 403}} = LegacyS3Bucket.get([], "missing")
  end

  test "refuses a source lease even when the caller acknowledges quiescence" do
    Tuist.Repo.query!(
      "INSERT INTO agent_sessions (id, kind, host, inserted_at, updated_at) VALUES ($1, 'thread', 'old-host', now(), now())",
      [Ecto.UUID.generate()]
    )

    assert {:error, :source_has_leases} =
             LuftConversationExport.export(quiesced: true, bucket: {EmptyBucket, []})
  end

  test "reads real legacy tables without loading conversation contexts" do
    assert {:ok, %{binary: binary, sha256: digest}} =
             LuftConversationExport.export(quiesced: true, bucket: {EmptyBucket, []})

    assert digest == Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
    assert %{"format" => "tuist-luft-conversations/1", "tables" => tables} = :erlang.binary_to_term(binary, [:safe])
    assert Map.has_key?(tables, "hall_members")
    assert Map.has_key?(tables, "thread_tool_calls")
  end

  test "decrypts actual Tuist Vault checkpoints, results and journal objects without changing source" do
    user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account])
    thread_id = Ecto.UUID.bingenerate()
    run_id = Ecto.UUID.bingenerate()
    checkpoint = <<0, 255, 10>>
    encrypted = Tuist.Vault.encrypt!(checkpoint)

    Tuist.Repo.query!(
      "INSERT INTO threads (id, account_id, owner_id, request_id, request_hash, title, goal, provider, model, inserted_at, updated_at) VALUES ($1,$2,$3,$4,$5,'history','retain','anthropic','test',now(),now())",
      [thread_id, user.account.id, user.id, Ecto.UUID.bingenerate(), <<1, 255>>]
    )

    Tuist.Repo.query!(
      "INSERT INTO thread_runs (id, thread_id, checkpoint, inserted_at, updated_at) VALUES ($1,$2,$3,now(),now())",
      [run_id, thread_id, encrypted]
    )

    Tuist.Repo.query!(
      "INSERT INTO thread_tool_calls (id, run_id, fingerprint, name, result, inserted_at, updated_at) VALUES ($1,$2,$3,'tool',$4,now(),now())",
      [Ecto.UUID.bingenerate(), run_id, <<255, 0>>, Tuist.Vault.encrypt!("private result")]
    )

    key = "agents/thread/#{Ecto.UUID.load!(thread_id)}/wal/00000000000000000001"
    journal = :erlang.term_to_binary({:records, ["private journal"]})
    objects = %{key => Tuist.Vault.encrypt!(journal)}
    assert {:ok, %{binary: binary}} = LuftConversationExport.export(quiesced: true, bucket: {MemoryBucket, objects})
    data = :erlang.binary_to_term(binary, [:safe])
    assert [%{"checkpoint" => ^checkpoint}] = data["tables"]["thread_runs"]
    assert [%{"result" => "private result", "fingerprint" => <<255, 0>>}] = data["tables"]["thread_tool_calls"]
    assert data["objects"][key] == journal
    assert data["accounts"] == [{user.account.id, user.account.name}]
    assert %{rows: [[^encrypted]]} = Tuist.Repo.query!("SELECT checkpoint FROM thread_runs WHERE id = $1", [run_id])

    Tuist.Repo.query!("UPDATE thread_runs SET checkpoint = $1 WHERE id = $2", ["corrupt", run_id])
    assert {:error, :export_failed} = LuftConversationExport.export(quiesced: true, bucket: {MemoryBucket, objects})
  end
end
