defmodule TuistOps.ProjectAccess.PolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.ProjectAccess.Policy

  setup :verify_on_exit!

  describe "requester_allowed?/1" do
    test "true for an operator-domain subject" do
      assert Policy.requester_allowed?("marek@tuist.dev")
      assert Policy.requester_allowed?("MAREK@TUIST.DEV")
    end

    test "false for a non-operator domain" do
      refute Policy.requester_allowed?("attacker@evil.com")
      refute Policy.requester_allowed?("marek@tuist.dev.evil.com")
    end

    test "false for nil or empty" do
      refute Policy.requester_allowed?(nil)
      refute Policy.requester_allowed?("")
    end
  end

  describe "admin_approver_allowed?/1" do
    test "true for Owner and Admin tailnet roles" do
      stub(TailscaleClient, :user_role, fn _ -> {:ok, :owner} end)
      assert Policy.admin_approver_allowed?("owner@tuist.dev")

      stub(TailscaleClient, :user_role, fn _ -> {:ok, :admin} end)
      assert Policy.admin_approver_allowed?("admin@tuist.dev")
    end

    test "false for a Member (engineer)" do
      stub(TailscaleClient, :user_role, fn _ -> {:ok, :member} end)
      refute Policy.admin_approver_allowed?("eng@tuist.dev")
    end

    test "false when the tailnet lookup fails" do
      stub(TailscaleClient, :user_role, fn _ -> {:error, :not_found} end)
      refute Policy.admin_approver_allowed?("ghost@tuist.dev")
    end

    test "false for a nil approver" do
      refute Policy.admin_approver_allowed?(nil)
    end
  end
end
