defmodule Tuist.Ops.ClickHouseIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo
  alias Tuist.Ops.ClickHouse
  alias Tuist.Release

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end

  test "executes a typed, bounded query against ClickHouse" do
    assert {:ok,
            %{
              columns: ["number"],
              rows: [%{"number" => 0}, %{"number" => 1}],
              num_rows: 2,
              truncated?: true
            }} =
             ClickHouse.execute(
               "SELECT number FROM numbers({count:UInt64}) ORDER BY number",
               params: %{"count" => 5},
               limit: 2
             )
  end

  test "executes the operator identity reconciliation against ClickHouse" do
    suffix = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    username = "tuist_ops_test_#{suffix}"
    role = "tuist_ops_readonly_test_#{suffix}"
    database = IngestRepo.config() |> Keyword.fetch!(:database) |> to_string()
    password_hash = :sha256 |> :crypto.hash("test-password") |> Base.encode16(case: :lower)
    params = %{"username" => username, "role" => role}

    try do
      database
      |> Release.ops_clickhouse_reconciliation_queries(username, role, password_hash)
      |> Enum.each(fn {statement, query_params} ->
        IngestRepo.query!(statement, query_params, log: false)
      end)

      assert %{rows: [[1]]} =
               IngestRepo.query!(
                 """
                 SELECT count()
                 FROM system.role_grants
                 WHERE user_name = {username:String}
                   AND granted_role_name = {role:String}
                   AND granted_role_is_default = 1
                 """,
                 params,
                 log: false
               )

      connection_options =
        IngestRepo.config()
        |> Keyword.take([:hostname, :port, :scheme, :database, :transport_opts])
        |> Keyword.merge(
          username: username,
          password: "test-password",
          settings: [max_threads: 2, max_memory_usage: 1024 * 1024 * 1024]
        )

      {:ok, restricted_connection} = Ch.start_link(connection_options)

      try do
        assert %Ch.Result{rows: [[^username, 1]]} =
                 Ch.query!(restricted_connection, "SELECT currentUser(), 1")

        assert {:error, %Ch.Error{code: error_code}} =
                 Ch.query(
                   restricted_connection,
                   "CREATE TABLE forbidden_operator_write (value UInt8) ENGINE = Memory"
                 )

        assert error_code in [164, 497]
      after
        GenServer.stop(restricted_connection)
      end
    after
      IngestRepo.query!("DROP USER IF EXISTS `#{username}`", [], log: false)
      IngestRepo.query!("DROP ROLE IF EXISTS `#{role}`", [], log: false)
    end
  end
end
