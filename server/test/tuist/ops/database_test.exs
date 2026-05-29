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
