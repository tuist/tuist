defmodule Atlas.TuistServerTest do
  use ExUnit.Case, async: true

  alias Atlas.TuistServer

  defp respond(status, body), do: fn _req -> {:ok, %Req.Response{status: status, body: body}} end

  describe "query/2" do
    test "returns the decoded body on success" do
      body = %{"columns" => ["id"], "rows" => [%{"id" => 1}], "truncated" => false}

      assert {:ok, ^body} =
               TuistServer.query("SELECT 1",
                 token: "t",
                 base_url: "https://tuist.test",
                 request: respond(200, body)
               )
    end

    test "POSTs to the query endpoint with bearer auth and a JSON body" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      TuistServer.query("SELECT 1",
        limit: 5,
        token: "tok",
        base_url: "https://tuist.test/",
        request: request
      )

      assert_receive {:req, req}
      assert req.method == :post
      assert to_string(req.url) == "https://tuist.test/api/internal/atlas/db/query"
      assert req.options[:auth] == {:bearer, "tok"}
      assert req.options[:json] == %{"query" => "SELECT 1", "limit" => 5}
    end

    test "maps an error body to {:error, message}" do
      assert {:error, "Only SELECT..."} =
               TuistServer.query("DELETE FROM x",
                 token: "t",
                 base_url: "https://tuist.test",
                 request: respond(422, %{"error" => "Only SELECT..."})
               )
    end

    test "maps transport errors to a generic message" do
      request = fn _req -> {:error, %Mint.TransportError{reason: :econnrefused}} end

      assert {:error, "Could not reach the Tuist server."} =
               TuistServer.query("SELECT 1", token: "t", base_url: "https://tuist.test", request: request)
    end

    test "errors when neither a token nor a token path is configured" do
      assert {:error, message} =
               TuistServer.query("SELECT 1", base_url: "https://tuist.test", token: nil, token_path: nil)

      assert message =~ "not configured"
    end

    test "errors when the token file is missing" do
      assert {:error, message} =
               TuistServer.query("SELECT 1", base_url: "https://tuist.test", token_path: "/no/such/token")

      assert message =~ "Could not read Tuist server token"
    end
  end

  describe "describe_table/3" do
    test "GETs the table path, defaulting the schema to public" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      TuistServer.describe_table("accounts", "public", token: "t", base_url: "https://tuist.test", request: request)

      assert_receive {:req, req}
      assert req.method == :get
      assert to_string(req.url) == "https://tuist.test/api/internal/atlas/db/tables/public/accounts"
    end

    test "percent-encodes slashes in schema and table names so they can't traverse the path" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      TuistServer.describe_table("accounts/../../query", "public/../admin",
        token: "t",
        base_url: "https://tuist.test",
        request: request
      )

      assert_receive {:req, req}
      url = to_string(req.url)

      assert url ==
               "https://tuist.test/api/internal/atlas/db/tables/public%2F..%2Fadmin/accounts%2F..%2F..%2Fquery"

      refute url =~ "/db/tables/public/../"
    end
  end

  describe "clickhouse_query/2" do
    test "POSTs to the clickhouse endpoint with limit and named params" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{"columns" => [], "rows" => [], "num_rows" => 0, "truncated" => false}}}
      end

      TuistServer.clickhouse_query("SELECT count() FROM command_events",
        limit: 10,
        params: %{"project_ids" => [1, 2]},
        token: "tok",
        base_url: "https://tuist.test/",
        request: request
      )

      assert_receive {:req, req}
      assert req.method == :post
      assert to_string(req.url) == "https://tuist.test/api/internal/atlas/clickhouse/query"
      assert req.options[:auth] == {:bearer, "tok"}

      assert req.options[:json] == %{
               "query" => "SELECT count() FROM command_events",
               "limit" => 10,
               "params" => %{"project_ids" => [1, 2]}
             }
    end

    test "omits limit and params when not provided" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      TuistServer.clickhouse_query("SELECT 1", token: "t", base_url: "https://tuist.test", request: request)

      assert_receive {:req, req}
      assert req.options[:json] == %{"query" => "SELECT 1"}
    end

    test "maps a clickhouse error body to {:error, message}" do
      assert {:error, "query_failed"} =
               TuistServer.clickhouse_query("SELECT bad",
                 token: "t",
                 base_url: "https://tuist.test",
                 request: respond(422, %{"error" => "query_failed"})
               )
    end
  end

  describe "clickhouse_describe_table/3" do
    test "GETs the clickhouse table path with the database segment" do
      parent = self()

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: %{}}}
      end

      TuistServer.clickhouse_describe_table("command_events", "default",
        token: "t",
        base_url: "https://tuist.test",
        request: request
      )

      assert_receive {:req, req}
      assert req.method == :get
      assert to_string(req.url) == "https://tuist.test/api/internal/atlas/clickhouse/tables/default/command_events"
    end
  end

  describe "configured?/1" do
    test "false when no token is available" do
      refute TuistServer.configured?(base_url: "https://tuist.test", token_path: "/no/such/token")
    end

    test "false when base_url is missing" do
      refute TuistServer.configured?(base_url: nil, token: "t")
    end

    test "true with an explicit token and base_url" do
      assert TuistServer.configured?(base_url: "https://tuist.test", token: "t")
    end
  end
end
