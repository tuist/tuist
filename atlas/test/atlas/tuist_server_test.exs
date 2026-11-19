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

  describe "evaluate_feature_flags/2" do
    test "GETs resource evaluation with workload identity and query parameters, without a JSON body" do
      request = fn req ->
        assert req.method == :get
        assert to_string(req.url) == "https://tuist.test/api/internal/atlas/flags/evaluate"
        assert req.options[:params] == %{"project_id" => 123}
        assert req.options[:auth] == {:bearer, "tok"}
        refute Map.has_key?(req.options, :json)
        {:ok, %Req.Response{status: 200, body: %{"evaluations" => []}}}
      end

      assert {:ok, %{"evaluations" => []}} =
               TuistServer.evaluate_feature_flags(%{"project_id" => 123},
                 token: "tok",
                 base_url: "https://tuist.test/",
                 request: request
               )
    end

    test "preserves missing resource and invalid target errors" do
      for {status, reason} <- [{404, "resource_not_found"}, {422, "invalid_target"}] do
        assert {:error, ^reason} =
                 TuistServer.evaluate_feature_flags(%{"account_id" => 42},
                   token: "tok",
                   base_url: "https://tuist.test",
                   request: respond(status, %{"error" => reason})
                 )
      end
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

  describe "feature flags" do
    test "lists and inspects persisted rules through the internal workload-identity API" do
      parent = self()
      body = %{"flags" => []}

      request = fn req ->
        send(parent, {:req, req})
        {:ok, %Req.Response{status: 200, body: body}}
      end

      opts = [token: "tok", base_url: "https://tuist.test", request: request]
      assert {:ok, ^body} = TuistServer.list_feature_flags(opts)
      assert_receive {:req, req}
      assert req.method == :get
      assert req.url.path == "/api/internal/atlas/flags"
      assert req.options[:auth] == {:bearer, "tok"}

      assert {:ok, ^body} = TuistServer.get_feature_flag("flag/../../db", opts)
      assert_receive {:req, req}
      assert req.method == :get
      assert req.url.path == "/api/internal/atlas/flags/flag%2F..%2F..%2Fdb"
    end

    test "PUTs the complete mutation once with automatic retries disabled" do
      attrs = %{
        "operation" => "enable",
        "scope" => "percentage",
        "percentage" => 12.5,
        "expected_revision" => "revision",
        "change_id" => Ecto.UUID.generate(),
        "reason" => "Gradual rollout",
        "actor" => %{"id" => Ecto.UUID.generate(), "email" => "operator@tuist.dev"},
        "interface" => "mcp"
      }

      request = fn req ->
        assert req.method == :put
        assert req.url.path == "/api/internal/atlas/flags/rollout"
        assert req.options[:json] == attrs
        assert req.options[:retry] == false
        {:ok, %Req.Response{status: 409, body: %{"error" => "stale_revision"}}}
      end

      assert {:error, "stale_revision"} =
               TuistServer.update_feature_flag("rollout", attrs,
                 token: "tok",
                 base_url: "https://tuist.test",
                 request: request
               )
    end

    test "does not inspect transport failures which can contain credentials" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, "Could not reach the Tuist server."} =
                   TuistServer.update_feature_flag("rollout", %{},
                     token: "sensitive-test-token",
                     base_url: "https://tuist.test",
                     request: fn req -> {:error, %{request: req, secret: "sensitive-test-token"}} end
                   )
        end)

      assert log =~ "transport error"
      refute log =~ "sensitive-test-token"
    end
  end

  describe "get_kura_rollout/2" do
    test "GETs the active rollout without an id and a specific rollout with one" do
      body = %{"rollout" => %{"status" => "paused"}}
      id = Ecto.UUID.generate()

      for {arg, params} <- [{nil, nil}, {id, [id: id]}] do
        request = fn req ->
          assert req.method == :get
          assert req.url.path == "/api/internal/atlas/kura/rollout"
          assert req.options[:params] == params
          assert req.options[:auth] == {:bearer, "tok"}
          {:ok, %Req.Response{status: 200, body: body}}
        end

        assert {:ok, ^body} =
                 TuistServer.get_kura_rollout(arg, token: "tok", base_url: "https://tuist.test", request: request)
      end
    end
  end

  describe "runner billing" do
    test "GETs billing through the workload-identity endpoint and preserves the response" do
      body = %{"revision" => "billing-1", "activation" => nil}

      request = fn req ->
        assert req.method == :get
        assert req.url.path == "/api/internal/atlas/accounts/42/runner-billing"
        assert req.options[:auth] == {:bearer, "tok"}
        {:ok, %Req.Response{status: 200, body: body}}
      end

      assert {:ok, ^body} =
               TuistServer.get_runner_billing(42, token: "tok", base_url: "https://tuist.test", request: request)
    end

    test "PUTs activation once without retries, preserving success, conflict and partial-effect errors" do
      attrs = %{
        "paid_cents" => 100_000,
        "credit_multiplier" => "1.50",
        "platforms" => ["linux", "macos"],
        "starts_on" => "2026-11-01",
        "expires_on" => "2027-10-31",
        "invoice_id" => "in_paid123",
        "expected_revision" => "billing-1",
        "change_id" => Ecto.UUID.generate(),
        "reason" => "Paid runner order",
        "actor" => %{"id" => Ecto.UUID.generate(), "email" => "operator@tuist.dev"},
        "interface" => "mcp"
      }

      for {status, body, expected} <- [
            {200, %{"revision" => "billing-2"}, {:ok, %{"revision" => "billing-2"}}},
            {409, %{"error" => "stale_revision"}, {:error, "stale_revision"}},
            {422, %{"error" => "activation_failed"}, {:error, "activation_failed"}}
          ] do
        request = fn req ->
          assert req.method == :put
          assert req.url.path == "/api/internal/atlas/accounts/42/runner-billing"
          assert req.options[:auth] == {:bearer, "tok"}
          assert req.options[:json] == attrs
          assert req.options[:retry] == false
          send(self(), :activation_requested)
          {:ok, %Req.Response{status: status, body: body}}
        end

        assert ^expected =
                 TuistServer.activate_runner_prepaid_pool(42, attrs,
                   token: "tok",
                   base_url: "https://tuist.test",
                   request: request
                 )

        assert_received :activation_requested
        refute_received :activation_requested
      end
    end

    test "PUTs trial changes once to the runner trial endpoint without retries" do
      attrs = %{"operation" => "start", "change_id" => Ecto.UUID.generate()}

      request = fn req ->
        assert req.method == :put
        assert req.url.path == "/api/internal/atlas/accounts/42/runner-trial"
        assert req.options[:auth] == {:bearer, "tok"}
        assert req.options[:json] == attrs
        assert req.options[:retry] == false
        {:ok, %Req.Response{status: 409, body: %{"error" => "paid_plan_required"}}}
      end

      assert {:error, "paid_plan_required"} =
               TuistServer.update_runner_trial(42, attrs,
                 token: "tok",
                 base_url: "https://tuist.test",
                 request: request
               )
    end

    test "bounds ambiguous transport errors without logging credentials or retrying" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          request = fn req ->
            assert req.options[:retry] == false
            send(self(), :activation_requested)
            {:error, %{request: req, secret: "sensitive-runner-token"}}
          end

          assert {:error, "Could not reach the Tuist server."} =
                   TuistServer.activate_runner_prepaid_pool(42, %{"change_id" => Ecto.UUID.generate()},
                     token: "sensitive-runner-token",
                     base_url: "https://tuist.test",
                     request: request
                   )
        end)

      assert_received :activation_requested
      refute_received :activation_requested
      assert log =~ "transport error"
      refute log =~ "sensitive-runner-token"
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
