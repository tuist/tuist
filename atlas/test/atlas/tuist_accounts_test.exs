defmodule Atlas.TuistAccountsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit
  alias Atlas.MCP
  alias Atlas.MCP.Tools.ActivateTuistRunnerPrepaidPool
  alias Atlas.MCP.Tools.GetTuistAccount
  alias Atlas.MCP.Tools.GetTuistAccountPlan
  alias Atlas.MCP.Tools.GetTuistRunnerBilling
  alias Atlas.MCP.Tools.GetTuistRunnerConcurrencyLimits
  alias Atlas.MCP.Tools.UpdateTuistAccountPlan
  alias Atlas.MCP.Tools.UpdateTuistRunnerConcurrencyLimits
  alias Atlas.MCP.Tools.UpdateTuistRunnerTrial
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

  describe "plans" do
    defp plan(effective_plan, revision) do
      subscription = %{
        "subscription_id" => "sub_1",
        "plan" => "enterprise",
        "status" => "active",
        "cancel_at_period_end" => false,
        "current_period_start" => "2026-11-01T00:00:00Z",
        "current_period_end" => "2026-12-01T00:00:00Z",
        "trial_end" => nil,
        "created_at" => "2026-11-13T10:00:00Z",
        "updated_at" => "2026-11-13T10:00:00Z"
      }

      %{
        "account_id" => 42,
        "account_handle" => "acme",
        "stripe_customer_id" => "cus_1",
        "effective_plan" => effective_plan,
        "subscription" => if(effective_plan != "air", do: subscription),
        "recent_subscriptions" => [%{subscription | "status" => "canceled"}],
        "payment_failed" => false,
        "cache_access_blocked" => false,
        "revision" => revision
      }
    end

    defp plan_change(attrs \\ %{}) do
      Map.merge(
        %{
          "account_id" => 42,
          "operation" => "upgrade_to_enterprise",
          "expected_revision" => "revision-1",
          "reason" => "Enterprise contract signed",
          "change_id" => Ecto.UUID.generate()
        },
        attrs
      )
    end

    test "reads the plan of a Tuist account ID and audits the target" do
      user = insert_user!(%{scopes: ["feature_flags:read"]})
      result = plan("air", "revision-1")

      expect(TuistServer, :get_account_plan, fn 42 -> {:ok, result} end)
      assert {:ok, ^result} = execute_tool(GetTuistAccountPlan, mcp_conn(user), %{"account_id" => 42})

      {[activity], _} = Audit.list_activities(actor_id: user.id, action: "tuist_account_plan.inspected")
      assert activity.target_id == "42"
      assert activity.metadata == %{"status" => "ok", "revision" => "revision-1"}
    end

    test "plan changes run only after the caller approves the exact call, and audits leave billing details out" do
      user = insert_user!(%{scopes: ["feature_flags:write"]})
      conn = mcp_conn(user)
      result = plan("enterprise", "revision-2")

      args =
        plan_change(%{
          "billing_details" => %{
            "name" => "Acme",
            "email" => "ap@acme.test",
            "address" => %{
              "line1" => "1 Example Street",
              "city" => "Springfield",
              "postal_code" => "12345",
              "country" => "US"
            }
          }
        })

      expect(TuistServer, :update_account_plan, fn 42, attrs ->
        assert attrs ==
                 args
                 |> Map.delete("account_id")
                 |> Map.put("actor", %{"id" => user.id, "email" => user.email})
                 |> Map.put("interface", "mcp")

        {:ok, result}
      end)

      assert {:error, message} = execute_tool(UpdateTuistAccountPlan, conn, args)
      assert message =~ "/approvals/"
      [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
      assert approval.tool_name == "update-account-plan"

      # Another operation is a different call that the approval does not cover.
      other_call = args |> Map.put("operation", "cancel_at_period_end") |> Map.delete("billing_details")
      {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")
      assert {:error, _} = execute_tool(UpdateTuistAccountPlan, conn, other_call)

      assert {:ok, ^result} = execute_tool(UpdateTuistAccountPlan, conn, args)

      {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_account_plan.updated")
      assert [ok] = Enum.filter(activities, &(&1.metadata["status"] == "ok"))
      assert ok.target_id == "42"

      assert ok.metadata == %{
               "operation" => "upgrade_to_enterprise",
               "expected_revision" => "revision-1",
               "reason" => args["reason"],
               "change_id" => args["change_id"],
               "effective_plan" => "enterprise",
               "revision" => "revision-2",
               "status" => "ok"
             }
    end

    test "plan changes are refused without write scope, outside MCP, from Slack, or with invalid arguments" do
      writer = insert_user!(%{scopes: ["feature_flags:write"]})
      reader = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()
      reject(TuistServer, :update_account_plan, 2)

      assert {:error, _} = execute_tool(UpdateTuistAccountPlan, reader, plan_change())

      for assigns <- [
            %{audit_interface: "worker"},
            %{audit_interface: "api"},
            %{mcp_claims: %{"slack_agent" => "systems_investigator"}}
          ] do
        conn = %{assigns: Map.put(assigns, :current_user, writer)}
        assert {:error, _} = execute_tool(UpdateTuistAccountPlan, conn, plan_change())
      end

      address = %{"line1" => "1 Main St", "city" => "Berlin", "postal_code" => "10115", "country" => "DE"}
      details = %{"name" => "Acme", "email" => "ap@acme.test", "address" => address}

      for attrs <- [
            %{"operation" => "upgrade_to_pro"},
            %{"account_id" => "42"},
            %{"reason" => " "},
            %{"change_id" => "not-a-uuid"},
            %{"plan" => "enterprise"},
            %{"actor" => %{"id" => Ecto.UUID.generate(), "email" => "forged@tuist.dev"}},
            %{"billing_details" => Map.delete(details, "address")},
            %{"billing_details" => put_in(details, ["address", "country"], "Germany")},
            %{"billing_details" => put_in(details, ["address", "unit"], "4")}
          ] do
        assert {:error, _} = execute_tool(UpdateTuistAccountPlan, mcp_conn(writer), plan_change(attrs))
      end

      assert MCP.list_pending_tool_approvals(writer, server_names: ["tuist-server"]) == []
    end
  end

  describe "runner billing" do
    defp prepaid_change(attrs \\ %{}) do
      Map.merge(
        %{
          "account_id" => 42,
          "paid_cents" => 100_000,
          "credit_multiplier" => "1.50",
          "platforms" => ["linux", "macos"],
          "starts_on" => "2026-11-01",
          "expires_on" => "2027-10-31",
          "invoice_id" => "in_paid123",
          "expected_revision" => "billing-1",
          "reason" => "Activate paid runner order",
          "change_id" => Ecto.UUID.generate()
        },
        attrs
      )
    end

    defp runner_billing(args \\ nil) do
      %{
        "account_id" => 42,
        "account_handle" => "acme",
        "stripe_customer_id" => if(args, do: "cus_1"),
        "revision" => if(args, do: "billing-2", else: "billing-1"),
        "runner_trial" => %{"active" => is_nil(args), "started_at" => nil, "ended_at" => nil},
        "prepaid_grants" =>
          if(args,
            do: [
              %{
                "id" => "credgr_1",
                "currency" => "usd",
                "amount_cents" => 150_000,
                "available_cents" => 149_000,
                "expires_at" => "2027-11-01T00:00:00Z",
                "metadata" => %{"invoice_id" => args["invoice_id"]}
              }
            ],
            else: []
          ),
        "activation" =>
          if(args,
            do:
              args
              |> Map.take(~w(change_id starts_on expires_on platforms paid_cents credit_multiplier))
              |> Map.merge(%{
                "status" => "active",
                "error" => nil,
                "grant_id" => "credgr_1",
                "subscription_schedule_id" => "sub_sched_1"
              })
          )
      }
    end

    test "reads and validates billing schemas including nullable and nested states, and audits only the revision" do
      user = insert_user!(%{scopes: ["feature_flags:read"]})

      for result <- [runner_billing(), runner_billing(prepaid_change())] do
        expect(TuistServer, :get_runner_billing, fn 42 -> {:ok, result} end)
        assert {:ok, ^result} = execute_tool(GetTuistRunnerBilling, mcp_conn(user), %{"account_id" => 42})
      end

      schema = ExJsonSchema.Schema.resolve(Atlas.TuistAccounts.runner_billing_output_schema())
      assert {:error, _} = ExJsonSchema.Validator.validate(schema, Map.delete(runner_billing(), "runner_trial"))

      assert {:error, _} =
               ExJsonSchema.Validator.validate(schema, put_in(runner_billing(), ["runner_trial", "active"], "true"))

      {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_billing.inspected")
      assert length(activities) == 2
      assert Enum.all?(activities, &(&1.target_id == "42" and Enum.sort(Map.keys(&1.metadata)) == ~w(revision status)))
    end

    test "activation needs single-use approval for the exact payload and forwards trusted provenance" do
      user = insert_user!(%{scopes: ["feature_flags:write"]})
      conn = mcp_conn(user)
      args = prepaid_change()
      result = runner_billing(args)

      expect(TuistServer, :activate_runner_prepaid_pool, fn 42, attrs ->
        assert attrs ==
                 args
                 |> Map.delete("account_id")
                 |> Map.put("actor", %{"id" => user.id, "email" => user.email})
                 |> Map.put("interface", "mcp")

        {:ok, result}
      end)

      assert {:error, message} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, args)
      assert message =~ "/approvals/"
      [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
      assert approval.tool_name == "activate-runner-prepaid-pool"
      {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")

      assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, %{args | "paid_cents" => 200_000})
      assert {:ok, ^result} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, args)
      assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, args)

      {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_billing.activated")
      assert [ok] = Enum.filter(activities, &(&1.metadata["status"] == "ok"))
      assert ok.target_id == "42"
      assert ok.interface == "mcp"

      assert ok.metadata ==
               args |> Map.delete("account_id") |> Map.merge(%{"status" => "ok", "revision" => "billing-2"})
    end

    test "read and write scopes, authentication and shared Slack refusal apply to direct execution" do
      writer = insert_user!(%{scopes: ["feature_flags:write"]})
      reader = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()
      other = %{scopes: ["admin:write"]} |> insert_user!() |> mcp_conn()
      reject(TuistServer, :activate_runner_prepaid_pool, 2)
      reject(TuistServer, :get_runner_billing, 1)

      assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, reader, prepaid_change())

      slack =
        for context <- [
              %{audit_interface: "slack"},
              %{mcp_claims: %{"slack_agent" => "systems_investigator"}},
              %{audit_interface: "mcp", mcp_claims: %{"slack_agent" => "systems_investigator"}}
            ],
            do: %{assigns: Map.put(context, :current_user, writer)}

      for conn <- [other, %{} | slack] do
        assert {:error, _} = execute_tool(GetTuistRunnerBilling, conn, %{"account_id" => 42})
        assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, prepaid_change())
      end

      for interface <- ~w(worker api) do
        conn = %{assigns: %{current_user: writer, audit_interface: interface}}
        assert {:error, message} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, prepaid_change())
        assert message =~ "only callable over Atlas MCP"
      end
    end

    test "validates the entire activation before requesting approval" do
      user = insert_user!(%{scopes: ["feature_flags:write"]})
      conn = mcp_conn(user)
      reject(TuistServer, :activate_runner_prepaid_pool, 2)

      for attrs <- [
            %{"account_id" => 0},
            %{"account_id" => "42"},
            %{"paid_cents" => 0},
            %{"paid_cents" => -1},
            %{"paid_cents" => 1.5},
            %{"credit_multiplier" => 1.5},
            %{"credit_multiplier" => "NaN"},
            %{"credit_multiplier" => "1e3"},
            %{"credit_multiplier" => "1\n"},
            %{"credit_multiplier" => "0"},
            %{"credit_multiplier" => "-1"},
            %{"platforms" => []},
            %{"platforms" => ["linux", "linux"]},
            %{"platforms" => ["windows"]},
            %{"starts_on" => "2026-02-30"},
            %{"starts_on" => "2028-01-01"},
            %{"expires_on" => "2027-10-31T00:00:00Z"},
            %{"invoice_id" => "inv_123"},
            %{"invoice_id" => "in_"},
            %{"invoice_id" => "in_paid123\n"},
            %{"expected_revision" => ""},
            %{"expected_revision" => " "},
            %{"reason" => " "},
            %{"reason" => String.duplicate("a", 1001)},
            %{"change_id" => "not-a-uuid"},
            %{"actor" => %{"id" => user.id}},
            %{"interface" => "mcp"}
          ] do
        assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, prepaid_change(attrs))
      end

      args = prepaid_change()

      for field <- Map.keys(args) do
        assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, Map.delete(args, field))
      end

      assert MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"]) == []

      # Both endpoints are inclusive; a single-day, single-platform term is valid.
      assert {:error, message} =
               execute_tool(
                 ActivateTuistRunnerPrepaidPool,
                 conn,
                 prepaid_change(%{
                   "starts_on" => "2027-10-31",
                   "platforms" => ["macos"],
                   "credit_multiplier" => "1"
                 })
               )

      assert message =~ "/approvals/"
    end

    test "remote failures remain errors and require fresh approval before reconciliation with identical payload" do
      user = insert_user!(%{scopes: ["feature_flags:write"]})
      conn = mcp_conn(user)
      args = prepaid_change()

      for message <- ["stale_revision", "Could not reach the Tuist server."] do
        expect(TuistServer, :activate_runner_prepaid_pool, fn 42, attrs ->
          assert Map.take(attrs, Map.keys(args) -- ["account_id"]) == Map.delete(args, "account_id")
          {:error, message}
        end)

        assert {:error, _} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, args)
        [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
        {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")
        assert {:error, ^message} = execute_tool(ActivateTuistRunnerPrepaidPool, conn, args)
      end

      {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_billing.activated")
      assert length(activities) == 4
      assert Enum.all?(activities, &(&1.metadata["status"] == "error"))
      refute Enum.any?(activities, &Map.has_key?(&1.metadata, "revision"))
    end

    defp trial_change(attrs \\ %{}) do
      Map.merge(
        %{
          "account_id" => 42,
          "operation" => "cancel",
          "expected_revision" => "billing-1",
          "reason" => "Account moved to Pro",
          "change_id" => Ecto.UUID.generate()
        },
        attrs
      )
    end

    test "trial changes need single-use approval of the exact call, forward trusted provenance and are audited" do
      user = insert_user!(%{scopes: ["feature_flags:write"]})
      conn = mcp_conn(user)
      args = trial_change(%{"confirm_air_limits" => true})
      result = put_in(runner_billing(), ["runner_trial", "active"], false)

      expect(TuistServer, :update_runner_trial, fn 42, attrs ->
        assert attrs ==
                 args
                 |> Map.delete("account_id")
                 |> Map.put("actor", %{"id" => user.id, "email" => user.email})
                 |> Map.put("interface", "mcp")

        {:ok, result}
      end)

      assert {:error, message} = execute_tool(UpdateTuistRunnerTrial, conn, args)
      assert message =~ "/approvals/"
      [approval] = MCP.list_pending_tool_approvals(user, server_names: ["tuist-server"])
      assert approval.tool_name == "update-runner-trial"
      {:ok, _} = MCP.decide_tool_approval(user, approval.id, "approved")

      # Dropping the Air acknowledgment is a different call the approval does not cover.
      assert {:error, _} = execute_tool(UpdateTuistRunnerTrial, conn, Map.delete(args, "confirm_air_limits"))
      assert {:ok, ^result} = execute_tool(UpdateTuistRunnerTrial, conn, args)
      assert {:error, _} = execute_tool(UpdateTuistRunnerTrial, conn, args)

      {activities, _} = Audit.list_activities(actor_id: user.id, action: "tuist_runner_trial.updated")
      assert [ok] = Enum.filter(activities, &(&1.metadata["status"] == "ok"))
      assert ok.target_id == "42"

      assert ok.metadata ==
               args |> Map.delete("account_id") |> Map.merge(%{"status" => "ok", "revision" => "billing-1"})
    end

    test "trial changes are refused without write scope, outside MCP, from Slack, or with invalid arguments" do
      writer = insert_user!(%{scopes: ["feature_flags:write"]})
      reader = %{scopes: ["feature_flags:read"]} |> insert_user!() |> mcp_conn()
      reject(TuistServer, :update_runner_trial, 2)

      assert {:error, _} = execute_tool(UpdateTuistRunnerTrial, reader, trial_change())

      for assigns <- [
            %{audit_interface: "worker"},
            %{audit_interface: "api"},
            %{mcp_claims: %{"slack_agent" => "systems_investigator"}}
          ] do
        conn = %{assigns: Map.put(assigns, :current_user, writer)}
        assert {:error, _} = execute_tool(UpdateTuistRunnerTrial, conn, trial_change())
      end

      for attrs <- [
            %{"operation" => "restart"},
            %{"account_id" => "42"},
            %{"confirm_air_limits" => "yes"},
            %{"reason" => " "},
            %{"change_id" => "not-a-uuid"},
            %{"ended_at" => "2026-11-18T00:00:00Z"},
            %{"actor" => %{"id" => Ecto.UUID.generate(), "email" => "forged@tuist.dev"}}
          ] do
        assert {:error, _} = execute_tool(UpdateTuistRunnerTrial, mcp_conn(writer), trial_change(attrs))
      end

      assert MCP.list_pending_tool_approvals(writer, server_names: ["tuist-server"]) == []
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
