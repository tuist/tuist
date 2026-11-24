defmodule TuistWeb.API.SandboxesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Sandboxes.Workers.DeleteUploadWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.SandboxesController
  alias TuistWeb.Authentication

  require Logger

  setup %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, account: user.account}
  end

  defp token_conn(account, scopes) do
    build_conn()
    |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: scopes})
    |> put_req_header("content-type", "application/json")
  end

  describe "account flag" do
    test "answers 404 in production for an account without the sandboxes flag", %{conn: conn, account: account} do
      stub(Environment, :env, fn -> :prod end)
      stub(FunWithFlags, :enabled?, fn :sandboxes, [for: _account] -> false end)
      reject(&Capacity.place/1)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{})
        |> json_response(:not_found)

      assert response["message"] =~ "not enabled"

      conn
      |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions")
      |> json_response(:not_found)
    end
  end

  test "native API accepts the 24 GiB shape", %{conn: conn, account: account} do
    body = %{platform: "darwin", memory_mb: 24_576}

    expect(Capacity, :place, fn sandbox ->
      sandbox |> Ecto.Changeset.change(node_name: "mac-1", node_uid: "node-uid", resident: true) |> Repo.update!()
      {:ok, "mac-1"}
    end)

    expect(Nodes, :call, fn "mac-1", "create", args, _opts ->
      assert %{vcpus: 8, memory_mb: 24_576, template: "macos", node_uid: "node-uid"} = args
      {:ok, %{"template_tag" => "versioned-image"}}
    end)

    response = conn |> post(~p"/api/accounts/#{account.name}/sandboxes", body) |> json_response(:created)
    assert response["platform"] == "darwin"
    assert response["resident"] == true
    assert response["memory_mb"] == 24_576
  end

  test "an xcode_version boots that Xcode's macOS template and an unserved one is refused with the served list",
       %{conn: conn, account: account} do
    stub(Environment, :macos_sandbox_xcode_versions, fn -> ["26.6", "26.1.1"] end)

    expect(Capacity, :place, fn %Sandbox{platform: :darwin, template: "macos-xcode-26-1-1", vcpus: 8} = sandbox ->
      sandbox |> Ecto.Changeset.change(node_name: "mac-1", node_uid: "node-uid") |> Repo.update!()
      {:ok, "mac-1"}
    end)

    expect(Nodes, :call, fn "mac-1", "create", %{template: "macos-xcode-26-1-1"}, _opts -> {:ok, %{}} end)

    response =
      conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{xcode_version: "26.1.1"}) |> json_response(:created)

    assert %{"platform" => "darwin", "template" => "macos-xcode-26-1-1"} = response

    assert %{"message" => "xcode_version must be one of: 26.6, 26.1.1"} =
             conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{xcode_version: "26.1"}) |> json_response(400)

    assert %{"message" => "xcode_version is only supported on macOS (platform darwin)"} =
             conn
             |> post(~p"/api/accounts/#{account.name}/sandboxes", %{platform: "linux", xcode_version: "26.6"})
             |> json_response(400)
  end

  describe "Amp Orb dispatch" do
    test "marks only admission refusals as retryable", %{conn: conn, account: account} do
      for {reason, status, hint} <- [
            {:no_capacity, 503, ["admission"]},
            {{:host_busy, :ci}, 503, ["admission"]},
            {:sandbox_concurrency_limit, 429, ["admission"]},
            {:sandbox_account_busy, 409, ["admission"]},
            {:locked, 409, ["admission"]},
            {:orb_bootstrap_failed, 502, []},
            {:node_disconnected, 503, []}
          ] do
        expect(Sandboxes, :dispatch_amp_orb, fn _, _, _ -> {:error, reason} end)

        result =
          post(conn, ~p"/api/accounts/#{account.name}/sandboxes/amp-orbs/amp-thread", %{
            operation: "spawn",
            orb_token: "orb-fixture"
          })

        assert response(result, status)
        assert get_resp_header(result, "x-tuist-orb-retry") == hint
      end
    end

    test "requires a spawn token and validates the operation", %{conn: conn, account: account} do
      for params <- [
            %{operation: "spawn"},
            %{operation: "unknown"},
            %{operation: "spawn", orb_token: ""},
            %{operation: "spawn", orb_token: "token", amp_url: "http://amp.example.com"}
          ] do
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/amp-orbs/amp-thread", params)
        |> json_response(:bad_request)
      end
    end

    test "pause and delete of missing Orbs succeed without credentials", %{conn: conn, account: account} do
      for operation <- ["pause", "delete"] do
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/amp-orbs/amp-thread", %{operation: operation})
        |> response(:no_content)
      end
    end

    test "spawns through the account API and never returns the token", %{conn: conn, account: account} do
      stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
      expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert env["ORB_TOKEN"] == "orb-secret"
        {:ok, %{"exit_code" => 0}}
      end)

      assert "" ==
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/amp-orbs/amp-thread", %{
                 operation: "spawn",
                 orb_token: "orb-secret"
               })
               |> response(:no_content)

      assert %{account_id: account_id, amp_orb_id: "amp-thread"} = Repo.get_by!(Sandbox, amp_orb_id: "amp-thread")
      assert account_id == account.id
    end

    test "requires the account feature flag", %{conn: conn, account: account} do
      stub(Environment, :env, fn -> :prod end)
      stub(FunWithFlags, :enabled?, fn :sandboxes, [for: _account] -> false end)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/amp-orbs/amp-thread", %{operation: "pause"})
      |> json_response(:not_found)
    end

    test "cannot dispatch into another account", %{conn: conn} do
      other = AccountsFixtures.account_fixture()

      conn
      |> post(~p"/api/accounts/#{other.name}/sandboxes/amp-orbs/amp-thread", %{operation: "pause"})
      |> json_response(:forbidden)
    end
  end

  describe "agent environments" do
    test "creates, lists and deletes an agent environment without ever returning the key", %{
      conn: conn,
      account: account
    } do
      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_abc",
          environment_key: "sk-ant-secret",
          name: "prod",
          vcpus: 4,
          memory_mb: 8192
        })
        |> json_response(:created)

      assert %{"anthropic_environment_id" => "env_abc", "name" => "prod", "vcpus" => 4, "memory_mb" => 8192} = response
      refute Map.has_key?(response, "environment_key")
      refute inspect(response) =~ "sk-ant-secret"

      listed =
        conn
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments")
        |> json_response(:ok)

      assert [%{"id" => id, "anthropic_environment_id" => "env_abc", "enabled" => true}] = listed["agent_environments"]
      refute inspect(listed) =~ "sk-ant-secret"

      conn
      |> delete(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{id}")
      |> response(:no_content)

      assert %{"agent_environments" => []} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments") |> json_response(:ok)
    end

    test "connects a Claude Code environment, which keeps idle sessions for half an hour and starts its orchestrator",
         %{conn: conn, account: account} do
      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          kind: "claude_code",
          anthropic_environment_id: "ccpool_01mac",
          environment_key: "sk-ant-cc-secret",
          platform: "darwin"
        })
        |> json_response(:created)

      assert %{"kind" => "claude_code", "platform" => "darwin", "template" => "macos", "max_idle_seconds" => 1800} =
               response

      stub(Environment, :macos_sandbox_xcode_versions, fn -> ["26.6", "26.1.1"] end)

      assert %{"id" => id, "platform" => "darwin", "template" => "macos-xcode-26-1-1", "xcode_version" => "26.1.1"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
                 kind: "claude_code",
                 anthropic_environment_id: "ccpool_01mac_xcode",
                 environment_key: "sk-ant-cc-secret",
                 xcode_version: "26.1.1"
               })
               |> json_response(:created)

      assert %{"template" => "macos", "xcode_version" => nil} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{id}", %{xcode_version: nil})
               |> json_response(:ok)

      assert_enqueued(worker: Tuist.Sandboxes.ClaudeCodeReconciler)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          kind: "claude_code",
          anthropic_environment_id: "env_01managed",
          environment_key: "sk-ant-secret"
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "does not name a claude_code environment"
    end

    test "rejects invalid params", %{conn: conn, account: account} do
      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_abc",
          environment_key: "sk-ant-secret",
          vcpus: 0
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "enum"

      agent_environment_fixture(anthropic_environment_id: "env_taken")

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_taken",
          environment_key: "sk-ant-secret"
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "anthropic_environment_id has already been taken"
    end

    test "answers 404 for another account's agent environment", %{conn: conn, account: account} do
      other = agent_environment_fixture()

      conn
      |> delete(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{other.id}")
      |> json_response(:not_found)

      conn
      |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{other.id}", %{agent_model: "claude-opus-5"})
      |> json_response(:not_found)
    end

    test "stores the federation ids all or none and returns the account's issuer", %{conn: conn, account: account} do
      federation_ids = %{
        anthropic_organization_id: "00000000-0000-4000-8000-000000000001",
        anthropic_workspace_id: "wrkspc_01Abc",
        anthropic_service_account_id: "svac_01Abc",
        anthropic_federation_rule_id: "fdrl_01Abc"
      }

      created =
        conn
        |> post(
          ~p"/api/accounts/#{account.name}/sandboxes/agent-environments",
          Map.merge(federation_ids, %{anthropic_environment_id: "env_federated", environment_key: "sk-ant-secret"})
        )
        |> json_response(:created)

      assert %{
               "has_api_key" => false,
               "anthropic_organization_id" => "00000000-0000-4000-8000-000000000001",
               "anthropic_workspace_id" => "wrkspc_01Abc",
               "anthropic_service_account_id" => "svac_01Abc",
               "anthropic_federation_rule_id" => "fdrl_01Abc",
               "federation_issuer_url" => issuer_url,
               "federation_subject" => subject
             } = created

      assert String.ends_with?(issuer_url, "/oidc/accounts/#{account.id}")
      assert subject == "account:#{account.id}:agent-environment:#{created["id"]}"

      response =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{created["id"]}", %{
          anthropic_federation_rule_id: nil
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "anthropic_federation_rule_id"

      cleared =
        conn
        |> patch(
          ~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{created["id"]}",
          Map.new(federation_ids, fn {key, _value} -> {key, nil} end)
        )
        |> json_response(:ok)

      assert %{"anthropic_organization_id" => nil, "anthropic_federation_rule_id" => nil} = cleared
    end

    test "stores the agent settings, reports has_api_key and drops the cached agent when the model changes", %{
      conn: conn,
      account: account
    } do
      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_agent",
          environment_key: "sk-ant-secret",
          anthropic_api_key: "sk-ant-api",
          agent_model: "claude-opus-5",
          agent_system_prompt: "Be brief."
        })
        |> json_response(:created)

      assert %{
               "has_api_key" => true,
               "agent_model" => "claude-opus-5",
               "agent_system_prompt" => "Be brief.",
               "anthropic_agent_id" => nil
             } = created

      refute Map.has_key?(created, "anthropic_api_key")
      refute inspect(created) =~ "sk-ant-api"

      agent_environment = agent_environment_fixture(account: account, anthropic_agent_id: "agent_cached")

      listed =
        conn
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments")
        |> json_response(:ok)

      assert %{"has_api_key" => false, "anthropic_agent_id" => "agent_cached", "agent_model" => "claude-sonnet-5"} =
               Enum.find(listed["agent_environments"], &(&1["id"] == agent_environment.id))

      updated =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
          anthropic_api_key: "sk-ant-api-2"
        })
        |> json_response(:ok)

      assert %{"has_api_key" => true, "anthropic_agent_id" => "agent_cached", "agent_model" => "claude-sonnet-5"} =
               updated

      refute inspect(updated) =~ "sk-ant-api-2"

      assert %{"anthropic_agent_id" => nil, "agent_model" => "claude-opus-5", "has_api_key" => true} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
                 agent_model: "claude-opus-5"
               })
               |> json_response(:ok)

      response =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
          agent_model: ""
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "minLength"
    end

    test "sets a Claude Code environment's setup script and refuses one on other environments", %{
      conn: conn,
      account: account
    } do
      claude_code =
        agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_01linux")

      assert %{"setup_script" => "mise install\n"} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{claude_code.id}", %{
                 setup_script: "mise install\n"
               })
               |> json_response(:ok)

      managed_agents = agent_environment_fixture(account: account)

      response =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{managed_agents.id}", %{
          setup_script: "mise install\n"
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "setup_script"
    end
  end

  describe "authorization" do
    test "forbids a user outside the account", %{conn: conn, account: account} do
      other_user = AccountsFixtures.user_fixture()

      response =
        conn
        |> Authentication.put_current_user(other_user)
        |> get(~p"/api/accounts/#{account.name}/sandboxes")
        |> json_response(:forbidden)

      assert response["message"] =~ "not authorized"
    end

    test "forbids an account token without the sandboxes write scope", %{account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      for scopes <- [["account:runners:write"], ["ci"], ["mcp"]] do
        conn = token_conn(account, scopes)

        conn |> get(~p"/api/accounts/#{account.name}/sandboxes") |> json_response(:forbidden)
        conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{}) |> json_response(:forbidden)

        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/exec", %{command: "true"})
        |> json_response(:forbidden)
      end
    end

    test "forbids an account token for another account", %{account: account} do
      other_account = AccountsFixtures.organization_fixture(preload: [:account]).account
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)
      conn = token_conn(other_account, ["account:sandboxes:write"])

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}") |> json_response(:forbidden)
      conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{}) |> json_response(:forbidden)
    end

    test "requires authentication", %{account: account} do
      build_conn()
      |> get(~p"/api/accounts/#{account.name}/sandboxes")
      |> json_response(:unauthorized)
    end
  end

  describe "sandboxes" do
    test "creates a Linux sandbox with a picked CPU guarantee and refuses others", %{conn: conn, account: account} do
      stub(Capacity, :place, fn %{platform: :linux} -> {:ok, "node-a"} end)

      # The node weighs the VM's cgroup by its guarantee: the pick, or a
      # quarter vCPU per GiB of memory when that is more.
      expect(Nodes, :call, 2, fn "node-a", "create", %{vcpus: 16, cpu_guarantee_milli: milli}, _opts
                                 when milli in [2000, 4000] ->
        {:ok, %{"template_tag" => "sha-1"}}
      end)

      for {body, guaranteed} <- [
            {%{memory_mb: 4096, vcpus: 2, guaranteed_vcpus: 2}, 2},
            {%{memory_mb: 16_384, vcpus: 8, guaranteed_vcpus: 1}, 4}
          ] do
        assert %{"vcpus" => 16, "guaranteed_vcpus" => ^guaranteed} =
                 conn |> post(~p"/api/accounts/#{account.name}/sandboxes", body) |> json_response(:created)
      end

      for body <- [%{guaranteed_vcpus: 3}, %{platform: "darwin", vcpus: 8, memory_mb: 8192, guaranteed_vcpus: 2}] do
        assert %{"message" => message} =
                 conn |> post(~p"/api/accounts/#{account.name}/sandboxes", body) |> json_response(:bad_request)

        assert message =~ "guaranteed_cpu_milli"
      end
    end

    test "creates, inspects, runs commands in, pauses, resumes and deletes a sandbox", %{conn: conn, account: account} do
      stub(Capacity, :place, fn %{template: "default"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", %{vcpus: 16, memory_mb: 8192}, _opts ->
        {:ok, %{"template_tag" => "sha-1"}}
      end)

      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{vcpus: 4, memory_mb: 8192})
        |> json_response(:created)

      assert %{"id" => id, "state" => "running", "node_name" => "node-a", "vcpus" => 16, "template_tag" => "sha-1"} =
               created

      assert created["hostname"] == "sbx-" <> String.slice(id, 0, 8)

      assert %{"sandboxes" => [%{"id" => ^id}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes") |> json_response(:ok)

      assert %{"id" => ^id, "state" => "running"} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-lc", "echo hi"], timeout_ms: 2_000}, opts ->
        opts[:on_stream].({:stdout, "hi\n"})
        {:ok, %{"exit_code" => 0}}
      end)

      assert %{"exit_code" => 0, "stdout" => "hi\n", "stderr" => ""} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/exec", %{command: "echo hi", timeout_ms: 2_000})
               |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

      assert %{"state" => "paused", "paused_at" => paused_at} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/pause") |> json_response(:ok)

      assert is_binary(paused_at)

      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)

      assert %{"state" => "running", "paused_at" => nil} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/resume") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
      conn |> delete(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> response(:no_content)
      assert Repo.get(Sandbox, id) == nil
    end

    test "lists one filtered page with each sandbox's dashboard status", %{conn: conn, account: account} do
      now = DateTime.utc_now()
      idle = sandbox_fixture(account: account, state: :running, inserted_at: DateTime.add(now, -3, :minute))

      active =
        sandbox_fixture(
          account: account,
          state: :running,
          residency_work_id: "w-1",
          inserted_at: DateTime.add(now, -2, :minute)
        )

      failed =
        sandbox_fixture(
          account: account,
          state: :error,
          vcpus: 4,
          memory_mb: 8192,
          inserted_at: DateTime.add(now, -1, :minute)
        )

      sandbox_fixture(state: :running)

      assert %{
               "sandboxes" => [%{"id" => failed_id, "status" => "failed"}, %{"id" => active_id, "status" => "active"}],
               "pagination_metadata" => %{"total_count" => 3, "total_pages" => 2, "has_next_page" => true}
             } = conn |> get(~p"/api/accounts/#{account.name}/sandboxes?page_size=2") |> json_response(:ok)

      assert {failed_id, active_id} == {failed.id, active.id}

      assert %{"sandboxes" => [%{"id" => idle_id, "status" => "idle"}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes?page=2&page_size=2") |> json_response(:ok)

      assert idle_id == idle.id

      assert %{
               "sandboxes" => [%{"id" => ^idle_id}, %{"id" => ^active_id}],
               "pagination_metadata" => %{"total_count" => 2}
             } =
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes?vcpus=2&sort_order=asc")
               |> json_response(:ok)

      assert %{"sandboxes" => [%{"id" => ^failed_id}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes?status=failed") |> json_response(:ok)

      by_identifier =
        [failed, active, idle]
        |> Enum.sort_by(&(&1.amp_orb_id || &1.anthropic_session_id || &1.id))
        |> Enum.map(& &1.id)

      assert by_identifier ==
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes?sort_by=identifier")
               |> json_response(:ok)
               |> Map.fetch!("sandboxes")
               |> Enum.map(& &1["id"])

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes?status=sleeping") |> json_response(:bad_request)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes?sort_by=name") |> json_response(:bad_request)
    end

    test "queues the archive of a paused sandbox and refuses a running one", %{conn: conn, account: account} do
      paused = sandbox_fixture(account: account, state: :paused, node_name: "node-a", paused_at: DateTime.utc_now())
      running = sandbox_fixture(account: account, state: :running, node_name: "node-a")

      assert %{"id" => id, "state" => "paused"} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{paused.id}/archive") |> json_response(:accepted)

      assert_enqueued(worker: ArchiveSandboxesWorker, args: %{sandbox_id: id})

      assert conn
             |> post(~p"/api/accounts/#{account.name}/sandboxes/#{running.id}/archive")
             |> json_response(:conflict)
             |> Map.fetch!("message") =~ "running"
    end

    test "answers analytics for a range with the account's limits and validates the range", %{
      conn: conn,
      account: account
    } do
      sandbox_fixture(account: account, state: :running, vcpus: 4, memory_mb: 8192, workspace_gb: 10)
      finish = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      start = DateTime.utc_now() |> DateTime.add(-12, :hour) |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      assert %{
               "bucket" => "hour",
               "vcpu_hours" => vcpu_hours,
               "memory_gib_hours" => memory_gib_hours,
               "created" => %{"count" => 0, "points" => points},
               "concurrency" => %{
                 "limits" => %{"vcpus" => 32, "memory_gb" => 64.0},
                 # A quarter vCPU per GiB guaranteed.
                 "in_use" => %{"vcpus" => 2, "memory_gb" => 8.0}
               }
             } =
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics?start=#{start}&end=#{finish}")
               |> json_response(:ok)

      assert vcpu_hours == 0
      assert memory_gib_hours == 0
      assert length(points) in 12..13

      too_long = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.to_iso8601()

      conn
      |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics?start=#{too_long}")
      |> json_response(:bad_request)
    end

    test "answers 503 when no node can host the sandbox", %{conn: conn, account: account} do
      stub(Capacity, :place, fn _ -> {:error, :no_node} end)

      conn = post(conn, ~p"/api/accounts/#{account.name}/sandboxes", %{})

      assert json_response(conn, :service_unavailable)["message"] =~ "No sandbox node"
      # Longer than the CLI's retry budget, so it reports the error instead of replaying the wait.
      assert get_resp_header(conn, "retry-after") == ["300"]
    end

    test "answers 503 with the reason when the sandbox's archive store is not configured",
         %{conn: conn, account: account} do
      sandbox =
        sandbox_fixture(account: account, state: :archived, archive_key: "archives/gone", archive_store: "removed-store")

      conn = delete(conn, ~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}")

      assert json_response(conn, :service_unavailable)["message"] =~ "archive can't be reached"
    end

    test "answers fleet_busy with an honest retry-after once a create has waited for room", %{
      conn: conn,
      account: account
    } do
      test_pid = self()

      stub(Capacity, :place, fn _ ->
        send(test_pid, :placed)
        {:error, :no_capacity}
      end)

      conn = post(conn, ~p"/api/accounts/#{account.name}/sandboxes", %{})

      assert %{"code" => "fleet_busy", "message" => message} = json_response(conn, :service_unavailable)
      assert message =~ "Do not retry in a loop"
      assert get_resp_header(conn, "retry-after") == ["300"]
      # It placed again while it waited instead of answering the first refusal.
      assert_received :placed
      assert_received :placed
    end

    test "tells the account's limit apart from a busy fleet", %{conn: conn, account: account} do
      {:ok, _} = Tuist.Sandboxes.Concurrency.update_limits(account, %{sandbox_vcpus_limit: 1, sandbox_memory_gb_limit: 1})
      reject(&Capacity.place/1)

      conn = post(conn, ~p"/api/accounts/#{account.name}/sandboxes", %{})

      assert %{"code" => "account_limit"} = json_response(conn, :too_many_requests)
      assert get_resp_header(conn, "retry-after") == []
    end

    test "limits how fast an account creates sandboxes", %{conn: conn, account: account} do
      stub(Capacity, :place, fn _ -> {:error, :no_node} end)

      # The limit is a fixed one-minute window aligned to the clock, which a
      # burst crossing a minute boundary would split in two; start it after the
      # next boundary when one is close.
      until_next_window = 60_000 - rem(System.system_time(:millisecond), 60_000)
      if until_next_window < 10_000, do: Process.sleep(until_next_window + 50)

      for _ <- 1..10 do
        assert %{"code" => "no_node"} =
                 conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{}) |> json_response(:service_unavailable)
      end

      conn = post(conn, ~p"/api/accounts/#{account.name}/sandboxes", %{})

      assert %{"code" => "rate_limited"} = json_response(conn, :too_many_requests)
      assert [seconds] = get_resp_header(conn, "retry-after")
      assert String.to_integer(seconds) in 1..60
    end

    test "extends a sandbox's lifetime, and answers 409 for one an integration owns", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, lifetime_seconds: 7200, expires_at: DateTime.utc_now())
      orb = sandbox_fixture(account: account, amp_orb_id: "orb-1")
      reject(&Nodes.call/4)

      assert %{"lifetime_seconds" => 14_400, "expires_at" => expires_at} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/extend", %{lifetime_seconds: 14_400})
               |> json_response(:ok)

      {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 14_400, 5

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/extend", %{lifetime_seconds: 90_000})
      |> json_response(:bad_request)

      assert %{"message" => message} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{orb.id}/extend", %{})
               |> json_response(:conflict)

      assert message =~ "no lifetime"
    end

    test "answers 409 for an operation the sandbox state does not allow", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :paused)
      reject(&Nodes.call/4)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/pause")
        |> json_response(:conflict)

      assert response["message"] =~ "paused"
    end

    test "answers 502 when the node rejects the operation", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, "worker running"} end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/pause")
        |> json_response(:bad_gateway)

      assert response["message"] =~ "worker running"
    end

    test "answers 404 for unknown or foreign sandboxes", %{conn: conn, account: account} do
      foreign = sandbox_fixture()

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{foreign.id}") |> json_response(:not_found)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/not-a-uuid") |> json_response(:not_found)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{Ecto.UUID.generate()}/exec", %{command: "ls"})
      |> json_response(:not_found)
    end

    test "validates the exec body", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/exec", %{})
      |> json_response(:bad_request)
    end
  end

  describe "commands" do
    # The guest's read answer: a header line, then the stdout chunk.
    defp guest_read(header, stdout) do
      fn "node-a", "exec", _args, opts ->
        opts[:on_stream].({:stdout, header <> "\n" <> stdout})
        {:ok, %{"exit_code" => 0}}
      end
    end

    defp member_conn(conn, role) do
      admin = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
      member = AccountsFixtures.user_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(member, organization, role: role)
      {Authentication.put_current_user(conn, member), organization.account}
    end

    test "a member starts a command and streams its output to the exit", %{conn: conn} do
      {conn, account} = member_conn(conn, :user)
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert env["TUIST_COMMAND"] == "exec 'xcodebuild' '-scheme' 'My App'"
        {:ok, %{"exit_code" => 0}}
      end)

      assert %{"id" => id, "status" => "running"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{
                 command: "xcodebuild",
                 args: ["-scheme", "My App"]
               })
               |> json_response(:accepted)

      expect(Nodes, :call, guest_read("running - 6 0 -", "hello\n"))
      expect(Nodes, :call, guest_read("exited 0 12 0 -", "world\n"))

      response = get(conn, ~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{id}/logs?stdout_offset=0")

      assert response.status == 200
      assert response |> get_resp_header("content-type") |> hd() =~ "application/x-ndjson"

      assert response.resp_body |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1) == [
               %{"type" => "stdout", "data" => "hello\n", "offset" => 6},
               %{"type" => "stdout", "data" => "world\n", "offset" => 12},
               %{"type" => "exit", "status" => "exited", "exit_code" => 0}
             ]

      assert %{"commands" => [%{"id" => ^id, "status" => "exited", "exit_code" => 0}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands") |> json_response(:ok)
    end

    # The environment the next command launches with.
    defp command_env(conn, account, sandbox, body) do
      test = self()

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        send(test, {:env, env})
        {:ok, %{"exit_code" => 0}}
      end)

      %{"id" => id} =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", body)
        |> json_response(:accepted)

      assert_received {:env, env}
      {id, env}
    end

    defp exchange(token) do
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/auth/oidc/token", %{token: token})
    end

    test "a member's command signs in to the account's cache while it runs", %{conn: conn} do
      {conn, account} = member_conn(conn, :user)
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")

      {id, env} = command_env(conn, account, sandbox, %{command: "tuist cache", timeout_ms: 600_000})

      assert env["TUIST_URL"] == Environment.app_url()
      assert "tuist-sandbox-" <> _ = token = env["TUIST_OIDC_TOKEN"]
      refute inspect(Repo.get!(SandboxCommand, id)) =~ token

      response = token |> exchange() |> json_response(:ok)
      {:ok, claims} = Tuist.Guardian.decode_and_verify(response["access_token"])
      assert claims["sub"] == to_string(account.id)
      assert claims["scopes"] == ["ci"]
      assert claims["all_projects"] == true
      # Never past the command's deadline.
      assert response["expires_in"] in 590..601

      # A forged or altered token is refused.
      assert token |> String.slice(0..-2//1) |> exchange() |> json_response(:unauthorized)

      # Once the command ended, its token no longer exchanges.
      SandboxCommand |> Repo.get!(id) |> Ecto.Changeset.change(status: :exited) |> Repo.update!()
      assert token |> exchange() |> json_response(:unauthorized)

      # Variables the caller sends win.
      {_id, env} = command_env(conn, account, Repo.reload!(sandbox), %{command: "true", env: %{"TUIST_URL" => "x"}})
      assert env["TUIST_URL"] == "x"
      assert env["TUIST_OIDC_TOKEN"] != token
    end

    test "a command's credential is never broader than its starter's cache access", %{conn: conn} do
      {member, account} = member_conn(conn, :user)
      {:ok, account} = Tuist.Accounts.update_account(account, %{cache_write_policy: :tokens_only})
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")

      # Members of an account whose cache only tokens write only read it.
      {_id, env} = command_env(member, account, sandbox, %{command: "true"})

      {:ok, claims} =
        env["TUIST_OIDC_TOKEN"]
        |> exchange()
        |> json_response(:ok)
        |> then(&Tuist.Guardian.decode_and_verify(&1["access_token"]))

      assert claims["scopes"] == ["account:cache:read", "project:cache:read"]

      # A token without cache access gets the environment but no credential.
      sandbox = Repo.reload!(sandbox)
      {_id, env} = command_env(token_conn(account, ["account:sandboxes:write"]), account, sandbox, %{command: "true"})
      assert env["TUIST_URL"]
      refute Map.has_key?(env, "TUIST_OIDC_TOKEN")

      # A token keeps its own projects and the CI scopes it holds, never the sandboxes scope.
      project_token =
        build_conn()
        |> assign(:current_subject, %AuthenticatedAccount{
          account: account,
          scopes: ["account:sandboxes:write", "account:cache:write", "project:cache:write"],
          all_projects: false,
          project_ids: [42]
        })
        |> put_req_header("content-type", "application/json")

      {_id, env} = command_env(project_token, account, Repo.reload!(sandbox), %{command: "true"})

      {:ok, claims} =
        env["TUIST_OIDC_TOKEN"]
        |> exchange()
        |> json_response(:ok)
        |> then(&Tuist.Guardian.decode_and_verify(&1["access_token"]))

      assert claims["scopes"] == ["account:cache:write", "project:cache:write"]
      assert claims["project_ids"] == [42]
      refute claims["all_projects"]
    end

    test "an administrator's command in an agent's sandbox gets no Tuist credential", %{conn: conn, account: account} do
      environment = agent_environment_fixture(account: account)

      sandbox =
        sandbox_fixture(account: account, state: :running, node_name: "node-a", agent_environment_id: environment.id)

      {_id, env} = command_env(conn, account, sandbox, %{command: "true"})
      refute Map.has_key?(env, "TUIST_OIDC_TOKEN")
      refute Map.has_key?(env, "TUIST_URL")
    end

    @tag :tmp_dir
    test "refuses a working directory missing in the sandbox with 400", %{conn: conn, account: account, tmp_dir: home} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      missing = Path.join(home, "does-not-exist")

      # Runs the real start script. The guest agent cannot start a process in
      # a missing directory, so the exec itself must run in the workspace.
      expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-c", script], cwd: cwd, env: env}, _opts ->
        assert cwd == Sandboxes.workspace(sandbox)
        {_output, code} = System.cmd("/bin/bash", ["-c", script], env: Map.put(env, "HOME", home), cd: home)
        {:ok, %{"exit_code" => code}}
      end)

      assert %{"message" => message} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{
                 command: "true",
                 cwd: missing
               })
               |> json_response(:bad_request)

      assert message =~ missing

      assert conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands") |> json_response(:ok) == %{
               "commands" => []
             }

      refute File.exists?(Path.join(home, ".cache"))
    end

    test "ends the stream quietly when a later read fails after the client went away", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      %{"id" => id} =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{command: "sleep", args: ["600"]})
        |> json_response(:accepted)

      expect(Nodes, :call, guest_read("running - 0 0 -", ""))
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:error, "connection reset"} end)
      # Writing the error line finds the client's socket closed.
      expect(Plug.Adapters.Test.Conn, :chunk, fn _state, _body -> {:error, :closed} end)

      response = get(conn, ~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{id}/logs")

      assert response.status == 200
      assert response.state == :chunked
    end

    test "streams 404 as a plain status for an unknown command", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> get(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{Ecto.UUID.generate()}/logs")
      |> json_response(:not_found)
    end

    # Every request that reaches inside a sandbox: runs a command in it,
    # reads or drives one, or hands it files.
    defp guest_requests(sandbox) do
      command = Ecto.UUID.generate()

      [
        {:post, "#{sandbox.id}/exec", %{command: "cat /proc/*/environ"}},
        {:post, "#{sandbox.id}/commands", %{command: "env"}},
        {:get, "#{sandbox.id}/commands", %{}},
        {:get, "#{sandbox.id}/commands/#{command}", %{}},
        {:get, "#{sandbox.id}/commands/#{command}/logs", %{}},
        {:post, "#{sandbox.id}/commands/#{command}/stdin", %{data: Base.encode64("x")}},
        {:post, "#{sandbox.id}/commands/#{command}/cancel", %{}},
        {:post, "#{sandbox.id}/uploads", %{}}
      ]
    end

    defp assert_guest_forbidden(conn, account, sandbox) do
      for {method, path, body} <- guest_requests(sandbox) do
        response = dispatch(conn, @endpoint, method, "/api/accounts/#{account.name}/sandboxes/#{path}", body)
        assert %{"code" => "forbidden"} = json_response(response, :forbidden), "#{method} #{path}"
      end
    end

    # Integration sandboxes: a Claude Code session's, whose runner holds the
    # session's work order, and an Amp Orb's, with someone's checkout.
    defp integration_sandboxes(account) do
      environment = agent_environment_fixture(account: account, kind: :claude_code, anthropic_environment_id: "ccpool_01")

      session =
        sandbox_fixture(
          account: account,
          state: :running,
          node_name: "node-a",
          agent_environment_id: environment.id,
          anthropic_session_id: "session-1"
        )

      orb = sandbox_fixture(account: account, state: :running, node_name: "node-a", amp_orb_id: "orb-1")
      {environment, [session, orb]}
    end

    test "a member reaches inside only plain sandboxes, and still manages an agent's or an Orb's", %{conn: conn} do
      {conn, account} = member_conn(conn, :user)
      {environment, sandboxes} = integration_sandboxes(account)

      paused =
        sandbox_fixture(
          account: account,
          state: :paused,
          paused_at: DateTime.utc_now(),
          agent_environment_id: environment.id
        )

      reject(&Nodes.call/4)

      for sandbox <- sandboxes do
        assert_guest_forbidden(conn, account, sandbox)
        id = sandbox.id
        assert %{"id" => ^id} = conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> json_response(:ok)
      end

      assert %{"id" => paused_id} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{paused.id}/archive") |> json_response(:accepted)

      assert_enqueued(worker: ArchiveSandboxesWorker, args: %{sandbox_id: paused_id})
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics") |> json_response(:ok)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments") |> json_response(:forbidden)
    end

    test "an administrator runs commands in an agent's sandbox, and the log names who did", %{
      conn: conn,
      account: account,
      user: user
    } do
      {_environment, [session, _orb]} = integration_sandboxes(account)
      Logger.put_module_level(SandboxesController, :info)
      on_exit(fn -> Logger.delete_module_level(SandboxesController) end)

      expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-lc", "echo secret"]}, _opts ->
        {:ok, %{"exit_code" => 0}}
      end)

      log =
        capture_log([level: :info], fn ->
          conn
          |> post(~p"/api/accounts/#{account.name}/sandboxes/#{session.id}/exec", %{command: "echo secret"})
          |> json_response(:ok)
        end)

      assert log =~ "sandboxes: exec in #{session.id} of account #{account.id} by user #{user.id}"
      refute log =~ "echo secret"
    end

    test "a viewer cannot run commands", %{conn: conn} do
      {conn, account} = member_conn(conn, :viewer)
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{command: "true"})
      |> json_response(:forbidden)
    end

    test "an account token with the sandboxes write scope creates, runs commands in and deletes a sandbox", %{
      account: account
    } do
      conn = token_conn(account, ["account:sandboxes:write"])
      stub(Capacity, :place, fn %{template: "default"} -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{"template_tag" => "sha-1"}} end)

      assert %{"id" => id, "state" => "running"} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes", %{}) |> json_response(:created)

      assert %{"sandboxes" => [%{"id" => ^id}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes") |> json_response(:ok)

      assert %{"id" => ^id} = conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-lc", "echo hi"]}, opts ->
        opts[:on_stream].({:stdout, "hi\n"})
        {:ok, %{"exit_code" => 0}}
      end)

      assert %{"exit_code" => 0, "stdout" => "hi\n"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/exec", %{command: "echo hi"})
               |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert %{"id" => command_id, "status" => "running"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/commands", %{command: "xcodebuild"})
               |> json_response(:accepted)

      assert %{"commands" => [%{"id" => ^command_id}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}/commands") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
      conn |> delete(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> response(:no_content)
      assert Repo.get(Sandbox, id) == nil
    end

    test "an account token, such as one a Claude Code session or an Orb exchanged, cannot reach inside integration sandboxes",
         %{account: account} do
      # The grant `OIDCController` gives a Claude Code session or an Amp Orb.
      conn =
        build_conn()
        |> assign(:current_subject, %AuthenticatedAccount{
          account: account,
          scopes: ["ci", "account:sandboxes:write"],
          all_projects: true
        })
        |> put_req_header("content-type", "application/json")

      {_environment, sandboxes} = integration_sandboxes(account)
      reject(&Nodes.call/4)

      for sandbox <- sandboxes do
        assert_guest_forbidden(conn, account, sandbox)
        id = sandbox.id
        assert %{"id" => ^id} = conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> json_response(:ok)
      end

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics") |> json_response(:ok)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments") |> json_response(:forbidden)
    end

    test "a member creates an upload, which is deleted once its URLs expire", %{conn: conn} do
      {conn, account} = member_conn(conn, :user)
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      other_sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      prefix = "sandbox-uploads/#{account.id}/#{sandbox.id}/"
      reject(&Nodes.call/4)

      expect(Tuist.Storage, :generate_upload_url, fn key, %{id: account_id}, [expires_in: 3600] ->
        assert account_id == account.id
        assert String.starts_with?(key, prefix)
        "https://storage/#{key}?put"
      end)

      expect(Tuist.Storage, :generate_download_url, fn key, _account, [expires_in: 3600] ->
        "https://storage/#{key}?get"
      end)

      assert %{
               "upload_url" => "https://storage/" <> upload,
               "download_url" => "https://storage/" <> download,
               "expires_at" => expires_at
             } =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/uploads")
               |> json_response(:ok)

      # Whole seconds: the CLI's generated client fails to decode fractional ones.
      assert expires_at =~ ~r/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/

      key = String.trim_trailing(upload, "?put")
      assert download == key <> "?get"
      assert [%Oban.Job{args: args, scheduled_at: scheduled_at}] = all_enqueued(worker: DeleteUploadWorker)
      assert args == %{"account_id" => account.id, "key" => key}
      assert DateTime.diff(scheduled_at, DateTime.utc_now()) > 3600

      expect(Tuist.Storage, :delete_object, fn ^key, %{id: account_id} when account_id == account.id -> :ok end)
      assert :ok = perform_job(DeleteUploadWorker, args)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{other_sandbox.id}/uploads")
      |> json_response(:not_found)
    end

    test "writes the decoded stdin bytes to the command", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      %{"id" => id} =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{command: "cat", stdin: true})
        |> json_response(:accepted)

      bytes = <<"hello", 0, 255, "\n">>

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert env["TUIST_STDIN_PARTS"] == "1"
        assert Base.decode64!(env["TUIST_STDIN_DATA_0"]) == bytes
        assert env["TUIST_STDIN_CLOSE"] == "1"
        {:ok, %{"exit_code" => 0}}
      end)

      assert %{"id" => ^id} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{id}/stdin", %{
                 data: Base.encode64(bytes),
                 close: true
               })
               |> json_response(:ok)
    end

    test "rejects stdin data that is not base64", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{Ecto.UUID.generate()}/stdin", %{
        data: "not base64!"
      })
      |> json_response(:bad_request)
    end
  end
end
