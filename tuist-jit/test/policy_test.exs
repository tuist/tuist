defmodule TuistJit.PolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistJit.Policy
  alias TuistJit.TailscaleClient

  setup :verify_on_exit!

  @owner "marek@tuist.dev"
  @admin "pedro@tuist.dev"
  @member "eduardo.ext@tuist.dev"
  @auditor "auditor@tuist.dev"
  @off_tailnet "attacker@evil.example"

  @staging "group:tuist-staging-write"
  @canary "group:tuist-canary-write"
  @prod "group:tuist-prod-write"

  # Stubs `TailscaleClient.user_role/1` against an in-test role map.
  # Off-map emails return {:error, :not_found} which is what the live
  # client does for unknown identities.
  defp stub_roles(roles) do
    stub(TailscaleClient, :user_role, fn email ->
      case Map.fetch(roles, email) do
        {:ok, role} -> {:ok, role}
        :error -> {:error, :not_found}
      end
    end)
  end

  describe "self_approval_allowed?/2" do
    test "Owner can self-approve any env" do
      stub_roles(%{@owner => :owner})

      for grp <- [@staging, @canary, @prod] do
        assert Policy.self_approval_allowed?(@owner, grp),
               "expected Owner #{@owner} to self-approve #{grp}"
      end
    end

    test "Admin can self-approve any env" do
      stub_roles(%{@admin => :admin})

      for grp <- [@staging, @canary, @prod] do
        assert Policy.self_approval_allowed?(@admin, grp),
               "expected Admin #{@admin} to self-approve #{grp}"
      end
    end

    test "Member can self-approve staging and canary" do
      stub_roles(%{@member => :member})

      assert Policy.self_approval_allowed?(@member, @staging)
      assert Policy.self_approval_allowed?(@member, @canary)
    end

    test "Member cannot self-approve production" do
      stub_roles(%{@member => :member})

      refute Policy.self_approval_allowed?(@member, @prod)
    end

    test "admin-flavor roles outside Owner/Admin cannot self-approve any env" do
      # Auditor / Billing admin / Network admin / IT admin are
      # tailnet admin-tier roles, but they're NOT engineering
      # identities. Default-deny.
      for role <- [:auditor, :billing_admin, :network_admin, :it_admin] do
        stub_roles(%{@auditor => role})

        for grp <- [@staging, @canary, @prod] do
          refute Policy.self_approval_allowed?(@auditor, grp),
                 "expected role #{role} to be denied for #{grp}"
        end
      end
    end

    test "off-tailnet identities cannot self-approve any env" do
      stub_roles(%{})

      for grp <- [@staging, @canary, @prod] do
        refute Policy.self_approval_allowed?(@off_tailnet, grp),
               "expected off-tailnet #{@off_tailnet} to be denied for #{grp}"
      end
    end

    test "unknown target groups default to deny, even for Owner" do
      stub_roles(%{@owner => :owner})

      refute Policy.self_approval_allowed?(@owner, "group:does-not-exist")
    end

    test "non-binary args fall through to deny" do
      refute Policy.self_approval_allowed?(nil, @staging)
      refute Policy.self_approval_allowed?(@member, nil)
      refute Policy.self_approval_allowed?(nil, nil)
    end
  end

  describe "approver_allowed?/2" do
    test "Owner can approve any env" do
      stub_roles(%{@owner => :owner})

      for grp <- [@staging, @canary, @prod] do
        assert Policy.approver_allowed?(@owner, grp)
      end
    end

    test "Admin can approve any env" do
      stub_roles(%{@admin => :admin})

      for grp <- [@staging, @canary, @prod] do
        assert Policy.approver_allowed?(@admin, grp)
      end
    end

    test "Member can approve staging and canary but NOT production" do
      # This is the new gate: an engineer approving another
      # engineer's production write is rejected.
      stub_roles(%{@member => :member})

      assert Policy.approver_allowed?(@member, @staging)
      assert Policy.approver_allowed?(@member, @canary)
      refute Policy.approver_allowed?(@member, @prod)
    end

    test "off-tailnet identities cannot approve any env" do
      stub_roles(%{})

      for grp <- [@staging, @canary, @prod] do
        refute Policy.approver_allowed?(@off_tailnet, grp)
      end
    end

    test "admin-flavor roles outside Owner/Admin cannot approve any env" do
      for role <- [:auditor, :billing_admin, :network_admin, :it_admin] do
        stub_roles(%{@auditor => role})

        for grp <- [@staging, @canary, @prod] do
          refute Policy.approver_allowed?(@auditor, grp),
                 "expected role #{role} to be denied as approver for #{grp}"
        end
      end
    end

    test "unknown target groups default to deny" do
      stub_roles(%{@owner => :owner})

      refute Policy.approver_allowed?(@owner, "group:does-not-exist")
    end

    test "non-binary args fall through to deny" do
      refute Policy.approver_allowed?(nil, @staging)
      refute Policy.approver_allowed?(@admin, nil)
    end
  end
end
