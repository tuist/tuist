defmodule Tuist.Ops.DatabaseTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Ops.Database

  describe "execute/2 grammar gate" do
    test "accepts SELECT" do
      assert {:ok, result} = Database.execute("SELECT 1 AS one")
      assert result.columns == ["one"]
      # Rows are wrapped as maps keyed by column name (+ a synthetic :id)
      # so they plug straight into Noora's <.table> in the LiveView.
      assert [%{:id => 0, "one" => 1}] = result.rows
      assert result.num_rows == 1
      refute result.truncated?
      assert is_integer(result.duration_us) and result.duration_us >= 0
    end

    test "accepts SELECT with leading whitespace and trailing semicolon" do
      assert {:ok, _} = Database.execute("   SELECT 1; ")
    end

    test "accepts WITH (CTE)" do
      assert {:ok, _} = Database.execute("WITH t AS (SELECT 1) SELECT * FROM t")
    end

    test "accepts EXPLAIN" do
      assert {:ok, _} = Database.execute("EXPLAIN SELECT 1")
    end

    test "accepts SHOW" do
      assert {:ok, _} = Database.execute("SHOW server_version")
    end

    test "rejects INSERT" do
      assert {:error, msg} = Database.execute("INSERT INTO accounts (name) VALUES ('x')")
      assert msg =~ "Only SELECT"
    end

    test "rejects UPDATE" do
      assert {:error, msg} = Database.execute("UPDATE accounts SET name = 'x'")
      assert msg =~ "Only SELECT"
    end

    test "rejects DELETE" do
      assert {:error, _} = Database.execute("DELETE FROM accounts")
    end

    test "rejects DROP" do
      assert {:error, _} = Database.execute("DROP TABLE accounts")
    end

    test "rejects TRUNCATE" do
      assert {:error, _} = Database.execute("TRUNCATE accounts")
    end

    test "rejects empty string" do
      assert {:error, "Empty query"} = Database.execute("")
      assert {:error, "Empty query"} = Database.execute("   \n\t  ;")
    end

    test "rejects non-string input" do
      assert {:error, "Query must be a string"} = Database.execute(nil)
      assert {:error, "Query must be a string"} = Database.execute(:select)
    end

    test "Postgres errors surface as :error tuples without crashing the LiveView" do
      assert {:error, msg} = Database.execute("SELECT * FROM definitely_not_a_table")
      assert is_binary(msg)
    end

    test "truncates large result sets" do
      sql = "SELECT generate_series(1, 500) AS n"
      assert {:ok, result} = Database.execute(sql, limit: 100)
      assert length(result.rows) == 100
      assert result.truncated?
    end
  end

  describe "execute/2 statement timeout" do
    test "configures Postgres `statement_timeout` for the read-only transaction" do
      # SHOW runs through the direct (non-cursor) path, but the SET LOCAL
      # in `run_read_only/2` applies regardless of path — this is the
      # cheap way to confirm the configuration actually reaches Postgres.
      assert {:ok, result} = Database.execute("SHOW statement_timeout")
      assert [%{"statement_timeout" => timeout}] = Enum.map(result.rows, &Map.delete(&1, :id))
      # Postgres normalizes the value depending on version: "5s" on
      # recent releases, "5000ms" on older ones. Either confirms the SET
      # LOCAL landed.
      assert timeout in ["5s", "5000ms"]
    end

    @tag timeout: 30_000
    test "Postgres aborts queries that exceed the timeout" do
      # `@statement_timeout_ms` is 5s; pg_sleep(10) deliberately
      # overshoots so we exercise the second enforcement layer
      # (Postgres-side abort) rather than just the grammar gate. The
      # error surfaces as `:error` with the canceled-statement message
      # instead of crashing the LiveView. Runs through the cursor path
      # (SELECT) on purpose to cover both gates simultaneously.
      assert {:error, msg} = Database.execute("SELECT pg_sleep(10)")
      assert msg =~ "canceling statement" or msg =~ "statement timeout"
    end
  end

  describe "export serializers" do
    setup do
      {:ok, result} =
        Database.execute("SELECT * FROM (VALUES (1, 'one'), (2, NULL)) AS t (n, label) ORDER BY n")

      {:ok, result: result}
    end

    test "to_markdown/1 wraps each row in a pipe table", %{result: result} do
      md = Database.to_markdown(result)
      assert md =~ "| n | label |"
      assert md =~ "| --- | --- |"
      assert md =~ "| 1 | one |"
      # nil renders as an empty cell so the row count is still correct.
      assert md =~ "| 2 |  |"
    end

    test "to_json/1 returns an array of column-keyed objects", %{result: result} do
      json = Database.to_json(result)
      decoded = JSON.decode!(json)
      assert [%{"n" => 1, "label" => "one"}, %{"n" => 2, "label" => nil}] = decoded
    end

    test "to_csv/1 renders an RFC 4180 CSV with header", %{result: result} do
      csv = Database.to_csv(result)
      assert csv == "n,label\n1,one\n2,"
    end

    test "to_csv/1 quotes cells containing commas or quotes" do
      {:ok, result} = Database.execute(~s|SELECT 'a, "b"' AS v|)
      assert Database.to_csv(result) == ~s|v\n"a, ""b"""|
    end

    # `Repo.query/1` has no schema-level casting, so a Postgres `uuid` comes
    # back as a raw 16-byte binary. Rendering it as-is would produce non-UTF-8
    # bytes and crash Jason with `invalid byte 0xBE` — the Hive incident that
    # motivated this fix routed through `Phoenix.Controller.json/2`. Both the
    # built-in `JSON` module and Jason reject invalid UTF-8, so the encoder
    # here pins the same regression.
    test "to_json_map/1 renders postgres uuid values as canonical UUID strings" do
      {:ok, result} = Database.execute("SELECT 'be426704-1c61-4e38-a7b5-e8bb42042a81'::uuid AS id")
      %{rows: [row]} = Database.to_json_map(result)
      assert row["id"] == "be426704-1c61-4e38-a7b5-e8bb42042a81"
      assert result |> Database.to_json_map() |> JSON.encode!() =~ "be426704-1c61-4e38-a7b5-e8bb42042a81"
    end

    test "to_json/1 renders postgres uuid values as canonical UUID strings" do
      {:ok, result} = Database.execute("SELECT 'be426704-1c61-4e38-a7b5-e8bb42042a81'::uuid AS id")
      json = Database.to_json(result)
      assert [%{"id" => "be426704-1c61-4e38-a7b5-e8bb42042a81"}] = JSON.decode!(json)
    end

    test "to_json_map/1 renders non-utf8 bytea values as postgres-style hex" do
      {:ok, result} = Database.execute(~s|SELECT '\\xdeadbe'::bytea AS b|)
      %{rows: [row]} = Database.to_json_map(result)
      assert row["b"] == "\\xdeadbe"
      assert result |> Database.to_json_map() |> JSON.encode!() =~ "\\\\xdeadbe"
    end

    # A `uuid[]` column would previously fall through to `inspect/1` (safe UTF-8
    # but rendered as an Elixir bitstring literal); the shared renderer now
    # recurses into lists so each element gets the same UUID / hex treatment.
    test "to_json_map/1 renders postgres uuid[] arrays element-by-element" do
      {:ok, result} =
        Database.execute(
          "SELECT ARRAY['be426704-1c61-4e38-a7b5-e8bb42042a81'::uuid, '00000000-0000-0000-0000-000000000000'::uuid] AS ids"
        )

      %{rows: [row]} = Database.to_json_map(result)

      assert row["ids"] == [
               "be426704-1c61-4e38-a7b5-e8bb42042a81",
               "00000000-0000-0000-0000-000000000000"
             ]

      assert result |> Database.to_json_map() |> JSON.encode!() =~
               "be426704-1c61-4e38-a7b5-e8bb42042a81"
    end

    # `numeric` arrives from Postgrex as `%Decimal{}`, and every SQL aggregate
    # (`avg`, `sum(bigint)`, `count(*) * 1.0`, `round`) returns `numeric`, so
    # the operator hits this on every summarising query — not a rare corner.
    # Emit it as a string so the scale Postgres sent survives the JSON hop.
    test "to_json_map/1 renders numeric/Decimal values as strings" do
      {:ok, result} = Database.execute("SELECT (1.0 * 3 / 2)::numeric(10,2) AS ratio")
      %{rows: [row]} = Database.to_json_map(result)
      assert row["ratio"] == "1.50"
    end

    # `jsonb` comes back from Postgrex as a plain map. Without the map clause,
    # the recursive `display_value/1` on `jsonb[]` would `inspect/1` each map
    # into an Elixir source string, and the CSV/markdown layer would then wrap
    # it in another layer of quoting. Keeping the map lets Jason emit a real
    # JSON object, which is what the Atlas consumer expects.
    test "to_json_map/1 keeps jsonb objects as maps" do
      {:ok, result} = Database.execute(~s|SELECT '{"a": 1, "b": "x"}'::jsonb AS payload|)
      %{rows: [row]} = Database.to_json_map(result)
      assert row["payload"] == %{"a" => 1, "b" => "x"}

      assert result |> Database.to_json_map() |> JSON.encode!() =~
               ~s|"payload":{"a":1,"b":"x"}|
    end

    test "to_json_map/1 keeps jsonb[] elements as JSON objects" do
      {:ok, result} =
        Database.execute(~s|SELECT ARRAY['{"attempt": 1}'::jsonb, '{"attempt": 2}'::jsonb] AS errors|)

      %{rows: [row]} = Database.to_json_map(result)
      assert row["errors"] == [%{"attempt" => 1}, %{"attempt" => 2}]
    end

    test "to_csv/1 does not crash on non-utf8 binary values" do
      {:ok, result} = Database.execute("SELECT 'be426704-1c61-4e38-a7b5-e8bb42042a81'::uuid AS id")
      assert Database.to_csv(result) == "id\nbe426704-1c61-4e38-a7b5-e8bb42042a81"
    end

    test "to_markdown/1 does not crash on non-utf8 binary values" do
      {:ok, result} = Database.execute("SELECT 'be426704-1c61-4e38-a7b5-e8bb42042a81'::uuid AS id")
      assert Database.to_markdown(result) =~ "be426704-1c61-4e38-a7b5-e8bb42042a81"
    end
  end

  describe "list_base_backups/0" do
    test "returns :not_configured when no CNPG namespace is wired" do
      stub(Environment, :cnpg_namespace, fn -> nil end)
      assert {:error, :not_configured} = Database.list_base_backups()
    end

    test "lists backups newest-first and parses CR fields" do
      stub(Environment, :cnpg_namespace, fn -> "tuist-staging" end)

      stub(K8sClient, :get, fn "/apis/postgresql.cnpg.io/v1/namespaces/tuist-staging/backups" ->
        {:ok,
         %{
           "items" => [
             %{
               "metadata" => %{"name" => "older", "creationTimestamp" => "2026-05-28T03:00:00Z"},
               "spec" => %{"method" => "barmanObjectStore", "cluster" => %{"name" => "tuist-tuist-pg"}},
               "status" => %{
                 "phase" => "completed",
                 "startedAt" => "2026-05-28T03:00:01Z",
                 "stoppedAt" => "2026-05-28T03:01:00Z"
               }
             },
             %{
               "metadata" => %{"name" => "newer", "creationTimestamp" => "2026-05-29T03:00:00Z"},
               "spec" => %{"method" => "barmanObjectStore", "cluster" => %{"name" => "tuist-tuist-pg"}},
               "status" => %{"phase" => "walArchivingFailing", "error" => "boom"}
             }
           ]
         }}
      end)

      assert {:ok, [first, second]} = Database.list_base_backups()

      assert first.name == "newer"
      assert first.phase == "walArchivingFailing"
      assert first.error == "boom"
      assert first.method == "barmanObjectStore"
      assert first.cluster == "tuist-tuist-pg"

      assert second.name == "older"
      assert second.phase == "completed"
      assert second.stopped_at == "2026-05-28T03:01:00Z"
      assert is_nil(second.error)
    end

    test "returns an empty list when the cluster has no backups" do
      stub(Environment, :cnpg_namespace, fn -> "tuist-staging" end)
      stub(K8sClient, :get, fn _path -> {:ok, %{"items" => []}} end)
      assert {:ok, []} = Database.list_base_backups()
    end

    test "returns :unavailable when the Kubernetes read fails" do
      stub(Environment, :cnpg_namespace, fn -> "tuist-staging" end)
      stub(K8sClient, :get, fn _path -> {:error, :not_found} end)
      assert {:error, :unavailable} = Database.list_base_backups()
    end
  end
end
