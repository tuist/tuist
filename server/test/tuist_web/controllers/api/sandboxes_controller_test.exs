defmodule TuistWeb.API.SandboxesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.DeleteUploadWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, account: user.account}
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

  describe "Amp Orb dispatch" do
    test "marks only admission refusals as retryable", %{conn: conn, account: account} do
      for {reason, status, hint} <- [
            {:no_capacity, 503, ["admission"]},
            {:sandbox_concurrency_limit, 429, ["admission"]},
            {:sandbox_account_busy, 409, ["admission"]},
            {:locked, 409, ["admission"]},
            {:orb_bootstrap_failed, 502, []},
            {:node_disconnected, 503, []}
          ] do
        expect(Tuist.Sandboxes, :dispatch_amp_orb, fn _, _, _ -> {:error, reason} end)

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
  end

  describe "authorization" do
    test "forbids a user who is not an admin of the account", %{conn: conn, account: account} do
      other_user = AccountsFixtures.user_fixture()

      response =
        conn
        |> Authentication.put_current_user(other_user)
        |> get(~p"/api/accounts/#{account.name}/sandboxes")
        |> json_response(:forbidden)

      assert response["message"] =~ "not authorized"
    end

    test "forbids an account token", %{account: account} do
      build_conn()
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> get(~p"/api/accounts/#{account.name}/sandboxes")
      |> json_response(:forbidden)
    end

    test "requires authentication", %{account: account} do
      build_conn()
      |> get(~p"/api/accounts/#{account.name}/sandboxes")
      |> json_response(:unauthorized)
    end
  end

  describe "sandboxes" do
    test "creates, inspects, runs commands in, pauses, resumes and deletes a sandbox", %{conn: conn, account: account} do
      stub(Capacity, :place, fn %{template: "default"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", %{vcpus: 4, memory_mb: 8192}, _opts ->
        {:ok, %{"template_tag" => "sha-1"}}
      end)

      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{vcpus: 4, memory_mb: 8192})
        |> json_response(:created)

      assert %{"id" => id, "state" => "running", "node_name" => "node-a", "vcpus" => 4, "template_tag" => "sha-1"} =
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

      assert_enqueued(worker: Tuist.Sandboxes.Workers.ArchiveSandboxesWorker, args: %{sandbox_id: id})

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
               "created" => %{"count" => 0, "points" => points},
               "concurrency" => %{
                 "limits" => %{"vcpus" => 32, "memory_gb" => 64.0, "disk_gb" => 420.0},
                 "in_use" => %{"vcpus" => 4, "memory_gb" => 8.0, "disk_gb" => 18.0}
               }
             } =
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics?start=#{start}&end=#{finish}")
               |> json_response(:ok)

      assert vcpu_hours == 0
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

    test "answers 503 when no node has memory or disk left", %{conn: conn, account: account} do
      stub(Capacity, :place, fn _ -> {:error, :no_capacity} end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{})
        |> json_response(:service_unavailable)

      assert response["message"] =~ "memory or disk"
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

    test "streams 404 as a plain status for an unknown command", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> get(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands/#{Ecto.UUID.generate()}/logs")
      |> json_response(:not_found)
    end

    test "a member cannot use an agent's sandbox or admin-only routes", %{conn: conn} do
      {conn, account} = member_conn(conn, :user)
      environment = agent_environment_fixture(account: account)

      sandbox =
        sandbox_fixture(account: account, state: :running, node_name: "node-a", agent_environment_id: environment.id)

      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{command: "env"})
      |> json_response(:forbidden)

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/analytics") |> json_response(:forbidden)
    end

    test "a viewer cannot run commands", %{conn: conn} do
      {conn, account} = member_conn(conn, :viewer)
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/commands", %{command: "true"})
      |> json_response(:forbidden)
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

      assert %{"upload_url" => "https://storage/" <> upload, "download_url" => "https://storage/" <> download} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/uploads")
               |> json_response(:ok)

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
