defmodule Atlas.TuistAccountsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit
  alias Atlas.MCP
  alias Atlas.MCP.Tools.GetTuistAccount
  alias Atlas.MCP.Tools.GetTuistRunnerConcurrencyLimits
  alias Atlas.MCP.Tools.UpdateTuistRunnerConcurrencyLimits
  alias Atlas.TuistServer

  setup :verify_on_exit!

  defp limits(revision \\ "revision-2") do
    %{
      "account_id" => 42,
      "account_handle" => "SteyCorp",
      "revision" => revision,
      "limits" => [
        %{
          "platform" => "linux",
          "vcpus" => 32,
          "memory_gb" => 64,
          "used_vcpus" => 0,
          "used_memory_gb" => 0,
          "default_vcpus" => 32,
          "default_memory_gb" => 64
        },
        %{
          "platform" => "macos",
          "vcpus" => 48,
          "memory_gb" => 144,
          "used_vcpus" => 12,
          "used_memory_gb" => 36,
          "default_vcpus" => 16,
          "default_memory_gb" => 48
        }
      ]
    }
  end

  defp approved_update(conn, args) do
    user = conn.assigns.current_user
    assert {:error, message} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, args)
    assert message =~ "approval"
    [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
    assert approval.tool_name == "update-runner-concurrency-limits"
    {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")
    execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, args)
  end

  defp mutation(attrs \\ %{}) do
    Map.merge(
      %{
        "account_id" => 42,
        "platform" => "macos",
        "vcpus" => 48,
        "memory_gb" => 144,
        "expected_revision" => "revision-1",
        "reason" => "Onboard SteyCorp to runners",
        "change_id" => Ecto.UUID.generate()
      },
      attrs
    )
  end

  test "lookup resolves a handle and audits the requested handle and resolved account" do
    user = insert_user!(%{scopes: ["feature_flags:read"]})

    account = %{
      "account_id" => 42,
      "handle" => "SteyCorp",
      "type" => "organization",
      "organization_id" => 3694,
      "user_id" => nil
    }

    expect(TuistServer, :lookup_account, fn "steycorp" -> {:ok, account} end)
    assert {:ok, ^account} = execute_tool(GetTuistAccount, mcp_conn(user), %{"handle" => "steycorp"})

    {[activity], _} = Audit.list_activities(actor_id: user.id, action: "tuist_account.looked_up")
    assert activity.metadata == %{"handle" => "steycorp", "account_id" => 42, "status" => "ok"}
  end

  test "reads limits for a Tuist account ID and audits the target" do
    user = insert_user!(%{scopes: ["feature_flags:read"]})
    result = limits()

    expect(TuistServer, :get_runner_concurrency_limits, fn 42 -> {:ok, result} end)
    assert {:ok, ^result} = execute_tool(GetTuistRunnerConcurrencyLimits, mcp_conn(user), %{"account_id" => 42})

    {[activity], _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_concurrency.inspected")
    assert activity.target_id == "42"
    assert activity.metadata == %{"status" => "ok", "revision" => "revision-2"}
  end

  test "updates run only after the caller approves the exact call, with actor and interface from execution" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    conn = mcp_conn(user)
    args = mutation()
    result = limits()

    expect(TuistServer, :update_runner_concurrency_limits, fn 42, attrs ->
      assert attrs ==
               args
               |> Map.delete("account_id")
               |> Map.put("actor", %{"id" => user.id, "email" => user.email})
               |> Map.put("interface", "mcp")

      {:ok, result}
    end)

    assert {:ok, ^result} = approved_update(conn, args)

    {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_concurrency.updated")
    assert [ok] = Enum.filter(activities, &(&1.metadata["status"] == "ok"))
    assert ok.interface == "mcp"
    assert ok.target_id == "42"
    assert ok.metadata["platform"] == "macos"
    assert ok.metadata["vcpus"] == 48
    assert ok.metadata["change_id"] == args["change_id"]
    assert ok.metadata["expected_revision"] == "revision-1"
    assert ok.metadata["revision"] == "revision-2"
  end

  test "an approval covers only its exact arguments, and worker or API contexts cannot write" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    conn = mcp_conn(user)
    reject(TuistServer, :update_runner_concurrency_limits, 2)

    args = mutation()
    assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, args)
    [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
    {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")

    assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, %{args | "vcpus" => 64})

    for interface <- ~w(worker api) do
      worker = %{assigns: %{current_user: user, audit_interface: interface}}
      assert {:error, message} = execute_tool(UpdateTuistRunnerConcurrencyLimits, worker, args)
      assert message =~ "only callable over Atlas MCP"
    end
  end

  test "readers cannot write, and callers without flag scopes or authentication cannot read" do
    reader = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()
    other = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()

    reject(TuistServer, :lookup_account, 1)
    reject(TuistServer, :get_runner_concurrency_limits, 1)
    reject(TuistServer, :update_runner_concurrency_limits, 2)

    assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, reader, mutation())

    for conn <- [other, %{}] do
      assert {:error, _} = execute_tool(GetTuistAccount, conn, %{"handle" => "SteyCorp"})
      assert {:error, _} = execute_tool(GetTuistRunnerConcurrencyLimits, conn, %{"account_id" => 42})
      assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, mutation())
    end
  end

  test "shared Slack contexts cannot directly execute these tools even with write scope" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    reject(TuistServer, :lookup_account, 1)
    reject(TuistServer, :get_runner_concurrency_limits, 1)
    reject(TuistServer, :update_runner_concurrency_limits, 2)

    for context <- [
          %{audit_interface: "slack"},
          %{mcp_claims: %{"slack_agent" => "systems_investigator"}},
          %{audit_interface: "mcp", mcp_claims: %{"slack_agent" => "systems_investigator"}}
        ],
        {tool, args} <- [
          {GetTuistAccount, %{"handle" => "SteyCorp"}},
          {GetTuistRunnerConcurrencyLimits, %{"account_id" => 42}},
          {UpdateTuistRunnerConcurrencyLimits, mutation()}
        ] do
      conn = %{assigns: Map.put(context, :current_user, user)}
      assert {:error, _} = execute_tool(tool, conn, args)
    end
  end

  test "rejects invalid targets, limits and forged provenance locally" do
    conn = %{scopes: ["feature_flags:write"]} |> insert_user!() |> mcp_conn()
    reject(TuistServer, :lookup_account, 1)
    reject(TuistServer, :get_runner_concurrency_limits, 1)
    reject(TuistServer, :update_runner_concurrency_limits, 2)

    for attrs <- [
          %{"account_id" => 0},
          %{"account_id" => "42"},
          %{"account_id" => Ecto.UUID.generate()},
          %{"account_id" => 9_223_372_036_854_775_808},
          %{"platform" => "windows"},
          %{"vcpus" => 0},
          %{"memory_gb" => -1},
          %{"vcpus" => 1.5},
          %{"vcpus" => 2_147_483_648},
          %{"reason" => " "},
          %{"reason" => String.duplicate("a", 1001)},
          %{"change_id" => "not-a-uuid"},
          %{"actor" => %{"id" => Ecto.UUID.generate(), "email" => "forged@tuist.dev"}},
          %{"interface" => "api"},
          %{"handle" => "SteyCorp"}
        ] do
      assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, mutation(attrs))
    end

    for field <- ~w(platform vcpus memory_gb expected_revision reason change_id) do
      assert {:error, _} = execute_tool(UpdateTuistRunnerConcurrencyLimits, conn, Map.delete(mutation(), field))
    end

    for args <- [%{}, %{"handle" => ""}, %{"handle" => " "}, %{"handle" => "a", "account_id" => 1}] do
      assert {:error, _} = execute_tool(GetTuistAccount, conn, args)
    end

    for args <- [%{}, %{"account_id" => -1}, %{"account_id" => 1, "platform" => "macos"}] do
      assert {:error, _} = execute_tool(GetTuistRunnerConcurrencyLimits, conn, args)
    end
  end

  test "conflicts and ambiguous transport failures remain errors with bounded outcome audits" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    args = mutation()

    for message <- ["stale_revision", "Could not reach the Tuist server."] do
      expect(TuistServer, :update_runner_concurrency_limits, fn 42, body ->
        assert body["change_id"] == args["change_id"]
        {:error, message}
      end)

      assert {:error, ^message} = approved_update(mcp_conn(user), args)
    end

    {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_concurrency.updated")
    # Two approval requests plus the two remote failures.
    assert length(activities) == 4
    assert Enum.all?(activities, &(&1.metadata["status"] == "error"))
    refute Enum.any?(activities, &Map.has_key?(&1.metadata, "revision"))
  end
end
