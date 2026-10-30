defmodule Atlas.TuistFeatureFlagsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit
  alias Atlas.Authorization
  alias Atlas.Authorization.Roles
  alias Atlas.MCP.Tools.EvaluateTuistFeatureFlags
  alias Atlas.MCP.Tools.GetTuistFeatureFlag
  alias Atlas.MCP.Tools.ListTuistFeatureFlags
  alias Atlas.MCP.Tools.UpdateTuistFeatureFlag
  alias Atlas.TuistServer

  setup :verify_on_exit!

  defp flag do
    %{
      "name" => "rollout",
      "actor_type" => "account",
      "description" => "Enabled means active; environment defaults may override evaluation.",
      "revision" => "revision-2",
      "gates" => [
        %{"type" => "boolean", "target" => nil, "enabled" => false},
        %{"type" => "actor", "target" => "account:1", "enabled" => true},
        %{"type" => "percentage_of_actors", "target" => "12.5", "enabled" => true}
      ]
    }
  end

  defp mutation(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "rollout",
        "operation" => "enable",
        "scope" => "global",
        "expected_revision" => "revision-1",
        "reason" => "Enable for a measured rollout",
        "change_id" => Ecto.UUID.generate()
      },
      attrs
    )
  end

  test "dedicated scopes are known, write implies read, and Member seeds exclude production flags" do
    assert Authorization.parse("feature_flags:read") == {:ok, "feature_flags", :read}
    assert Authorization.granted?(["feature_flags:write"], "feature_flags:read")
    refute Authorization.granted?(["admin:write"], "feature_flags:write")

    role = Roles.ensure_member_role!()
    refute "feature_flags:read" in role.scopes
    refute "feature_flags:write" in role.scopes
  end

  test "read tools preserve persisted gates and strictly validate structured content" do
    user = insert_user!(%{scopes: ["feature_flags:read"]})
    conn = mcp_conn(user)
    result = flag()

    expect(TuistServer, :list_feature_flags, fn -> {:ok, %{"flags" => [result]}} end)
    expect(TuistServer, :get_feature_flag, fn "rollout" -> {:ok, result} end)

    assert {:ok, %{"flags" => [^result]}} = execute_tool(ListTuistFeatureFlags, conn, %{})
    assert {:ok, ^result} = execute_tool(GetTuistFeatureFlag, conn, %{"name" => "rollout"})

    {activities, _} = Audit.list_activities(actor_id: user.id)
    assert Enum.any?(activities, &(&1.action == "tuist_feature_flag.listed" and &1.metadata["status"] == "ok"))
    assert Enum.any?(activities, &(&1.action == "tuist_feature_flag.inspected" and &1.target_id == "rollout"))
  end

  test "resource evaluation validates structured content and audits the requested Tuist target" do
    user = insert_user!(%{scopes: ["feature_flags:read"]})
    conn = mcp_conn(user)

    for target <- [%{"account_id" => 42}, %{"project_id" => 123}] do
      result = %{
        "environment" => "prod",
        "resource" => %{"account_id" => 42, "project_id" => target["project_id"]},
        "evaluations" => [
          %{
            "name" => "runners",
            "feature" => "runners",
            "description" => "Account enrollment with server environment defaults.",
            "actor_type" => "account",
            "actor_id" => 42,
            "enabled" => true
          }
        ]
      }

      expect(TuistServer, :evaluate_feature_flags, fn ^target -> {:ok, result} end)
      assert {:ok, ^result} = execute_tool(EvaluateTuistFeatureFlags, conn, target)
    end

    {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_feature_flag.evaluated")
    assert length(activities) == 2
    assert Enum.all?(activities, &(&1.metadata["status"] == "ok"))
    assert Enum.any?(activities, &(&1.metadata["account_id"] == 42))
    assert Enum.any?(activities, &(&1.metadata["project_id"] == 123))
    refute Enum.any?(activities, &Map.has_key?(&1.metadata, "evaluations"))
  end

  test "resource evaluation requires exactly one bounded positive Tuist resource ID" do
    conn = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()
    reject(TuistServer, :evaluate_feature_flags, 1)

    for args <- [
          %{},
          %{"account_id" => 1, "project_id" => 2},
          %{"account_id" => 0},
          %{"project_id" => -1},
          %{"account_id" => "42"},
          %{"account_id" => %{"private" => "untrusted payload"}},
          %{"project_id" => Ecto.UUID.generate()},
          %{"account_id" => 1.5},
          %{"project_id" => 9_223_372_036_854_775_808},
          %{"account_id" => 1, "actor" => %{}},
          %{"account_id" => 1, "environment" => "prod"}
        ] do
      assert {:error, _} = execute_tool(EvaluateTuistFeatureFlags, conn, args)
    end

    {activities, _} =
      Audit.list_activities(actor_id: conn.assigns.current_user.id, action: "tuist_feature_flag.evaluated")

    for activity <- activities, key <- ~w(account_id project_id), Map.has_key?(activity.metadata, key) do
      assert is_integer(activity.metadata[key])
      assert activity.metadata[key] > 0 and activity.metadata[key] <= 9_223_372_036_854_775_807
    end
  end

  test "evaluation transport errors are bounded and audited without remote response bodies" do
    user = insert_user!(%{scopes: ["feature_flags:read"]})
    expect(TuistServer, :evaluate_feature_flags, fn %{"account_id" => 42} -> {:error, "resource_not_found"} end)

    assert {:error, "resource_not_found"} =
             execute_tool(EvaluateTuistFeatureFlags, mcp_conn(user), %{"account_id" => 42})

    {[activity], _} = Audit.list_activities(actor_id: user.id, action: "tuist_feature_flag.evaluated")
    assert activity.metadata == %{"account_id" => 42, "status" => "error"}
  end

  test "direct execution rejects unauthenticated callers and users without dedicated scopes before remote calls" do
    conn = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
    reader = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()

    reject(TuistServer, :list_feature_flags, 0)
    reject(TuistServer, :get_feature_flag, 1)
    reject(TuistServer, :evaluate_feature_flags, 1)
    reject(TuistServer, :update_feature_flag, 2)

    assert {:error, _} = execute_tool(ListTuistFeatureFlags, %{}, %{})
    assert {:error, _} = execute_tool(ListTuistFeatureFlags, conn, %{})
    assert {:error, _} = execute_tool(GetTuistFeatureFlag, conn, %{"name" => "rollout"})
    assert {:error, _} = execute_tool(EvaluateTuistFeatureFlags, %{}, %{"account_id" => 42})
    assert {:error, _} = execute_tool(EvaluateTuistFeatureFlags, conn, %{"project_id" => 123})
    assert {:error, _} = execute_tool(UpdateTuistFeatureFlag, reader, mutation())
    assert {:error, _} = execute_tool(UpdateTuistFeatureFlag, conn, mutation())
  end

  test "shared Slack contexts cannot directly execute flag tools even with write scope" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    reject(TuistServer, :list_feature_flags, 0)
    reject(TuistServer, :get_feature_flag, 1)
    reject(TuistServer, :evaluate_feature_flags, 1)
    reject(TuistServer, :update_feature_flag, 2)

    for context <- [
          %{audit_interface: "slack"},
          %{mcp_claims: %{"slack_agent" => "systems_investigator"}},
          %{audit_interface: "mcp", mcp_claims: %{"slack_agent" => "systems_investigator"}}
        ],
        {tool, args} <- [
          {ListTuistFeatureFlags, %{}},
          {GetTuistFeatureFlag, %{"name" => "rollout"}},
          {EvaluateTuistFeatureFlags, %{"account_id" => 42}},
          {UpdateTuistFeatureFlag, mutation()}
        ] do
      conn = %{assigns: Map.put(context, :current_user, user)}
      assert {:error, _} = execute_tool(tool, conn, args)
    end
  end

  test "updates derive actor and interface from authenticated execution and retain the exact idempotent request" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    args = mutation(%{"scope" => "percentage", "percentage" => 12.5})
    result = flag()

    for interface <- ~w(mcp worker api) do
      conn = %{assigns: %{current_user: user, audit_interface: interface}}

      expect(TuistServer, :update_feature_flag, fn "rollout", attrs ->
        assert attrs ==
                 args
                 |> Map.delete("name")
                 |> Map.put("actor", %{"id" => user.id, "email" => user.email})
                 |> Map.put("interface", interface)

        {:ok, result}
      end)

      assert {:ok, ^result} = execute_tool(UpdateTuistFeatureFlag, conn, args)
    end

    {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_feature_flag.updated")
    assert length(activities) == 3
    assert Enum.sort(Enum.map(activities, & &1.interface)) == ~w(api mcp worker)

    for activity <- activities do
      assert activity.actor_email == user.email
      assert activity.metadata["change_id"] == args["change_id"]
      assert activity.metadata["reason"] == args["reason"]
      assert activity.metadata["expected_revision"] == "revision-1"
      assert activity.metadata["revision"] == "revision-2"
      assert activity.metadata["status"] == "ok"
    end
  end

  test "forwards each valid override, inheritance clear and explicit reset without inventing gate changes" do
    conn = %{scopes: ["feature_flags:write"]} |> insert_user!() |> mcp_conn()

    for attrs <- [
          %{"operation" => "disable", "scope" => "global"},
          %{"operation" => "clear", "scope" => "global"},
          %{"operation" => "enable", "scope" => "account", "account_id" => 123},
          %{"operation" => "disable", "scope" => "project", "project_id" => 456},
          %{"operation" => "clear", "scope" => "account", "account_id" => 123},
          %{"operation" => "clear", "scope" => "project", "project_id" => 456},
          %{"operation" => "clear", "scope" => "percentage"},
          %{"operation" => "clear", "scope" => "all"}
        ] do
      args = mutation(attrs)

      expect(TuistServer, :update_feature_flag, fn "rollout", body ->
        assert Map.drop(body, ~w(actor interface)) == Map.delete(args, "name")
        {:ok, flag()}
      end)

      assert {:ok, _} = execute_tool(UpdateTuistFeatureFlag, conn, args)
    end
  end

  test "rejects unknown fields, forged provenance, invalid targets and invalid rollout controls locally" do
    conn = %{scopes: ["feature_flags:write"]} |> insert_user!() |> mcp_conn()
    reject(TuistServer, :update_feature_flag, 2)

    for attrs <- [
          %{"actor" => %{"id" => Ecto.UUID.generate(), "email" => "forged@tuist.dev"}},
          %{"interface" => "api"},
          %{"extra" => true},
          %{"reason" => ""},
          %{"reason" => " "},
          %{"reason" => String.duplicate("a", 1001)},
          %{"expected_revision" => ""},
          %{"change_id" => "not-a-uuid"},
          %{"scope" => "all"},
          %{"operation" => "disable", "scope" => "percentage", "percentage" => 10},
          %{"scope" => "percentage", "percentage" => 0},
          %{"scope" => "percentage", "percentage" => 100},
          %{"scope" => "percentage", "percentage" => -1},
          %{"scope" => "percentage", "percentage" => 5.0e-324},
          %{"scope" => "percentage"},
          %{"scope" => "account"},
          %{"scope" => "account", "account_id" => 0},
          %{"scope" => "account", "account_id" => 9_223_372_036_854_775_808},
          %{"scope" => "project", "project_id" => 9_223_372_036_854_775_808},
          %{"scope" => "account", "account_id" => Ecto.UUID.generate()},
          %{"scope" => "project", "project_id" => 1.5},
          %{"scope" => "project", "project_id" => 1, "account_id" => 2},
          %{"account_id" => 1},
          %{"name" => ".."}
        ] do
      assert {:error, _} = execute_tool(UpdateTuistFeatureFlag, conn, mutation(attrs))
    end

    for field <- ~w(expected_revision reason change_id) do
      assert {:error, _} = execute_tool(UpdateTuistFeatureFlag, conn, Map.delete(mutation(), field))
    end

    assert {:error, _} = execute_tool(ListTuistFeatureFlags, conn, %{"extra" => true})
    assert {:error, _} = execute_tool(GetTuistFeatureFlag, conn, %{"name" => "rollout", "actor" => %{}})
  end

  test "conflicts and ambiguous transport failures remain errors with bounded outcome audits" do
    user = insert_user!(%{scopes: ["feature_flags:write"]})
    conn = mcp_conn(user)
    args = mutation()

    for message <- ["stale_revision", "Could not reach the Tuist server."] do
      expect(TuistServer, :update_feature_flag, fn "rollout", body ->
        assert body["expected_revision"] == args["expected_revision"]
        assert body["change_id"] == args["change_id"]
        {:error, message}
      end)

      assert {:error, ^message} = execute_tool(UpdateTuistFeatureFlag, conn, args)
    end

    {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_feature_flag.updated")
    assert length(activities) == 2
    assert Enum.all?(activities, &(&1.metadata["status"] == "error"))
    refute Enum.any?(activities, &Map.has_key?(&1.metadata, "revision"))
  end
end
