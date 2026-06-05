defmodule Tuist.TailscaleJIT.PolicyTest do
  use ExUnit.Case, async: true

  alias Tuist.TailscaleJIT.Policy

  @founders ["marek@tuist.dev", "pedro@tuist.dev"]
  @engineer "eduardo.ext@tuist.dev"
  @attacker "attacker@evil.example"

  @staging "group:tuist-staging-write"
  @canary "group:tuist-canary-write"
  @prod "group:tuist-prod-write"

  describe "self_approval_allowed?/2" do
    test "founders can self-approve any env" do
      for email <- @founders, grp <- [@staging, @canary, @prod] do
        assert Policy.self_approval_allowed?(email, grp),
               "expected #{email} to self-approve #{grp}"
      end
    end

    test "engineers can self-approve staging and canary" do
      assert Policy.self_approval_allowed?(@engineer, @staging)
      assert Policy.self_approval_allowed?(@engineer, @canary)
    end

    test "engineers cannot self-approve production" do
      refute Policy.self_approval_allowed?(@engineer, @prod)
    end

    test "unknown identities cannot self-approve any env" do
      for grp <- [@staging, @canary, @prod] do
        refute Policy.self_approval_allowed?(@attacker, grp),
               "expected #{@attacker} to be denied for #{grp}"
      end
    end

    test "unknown target groups default to deny, even for founders" do
      for email <- @founders do
        refute Policy.self_approval_allowed?(email, "group:does-not-exist")
      end
    end

    test "non-binary args fall through to deny" do
      refute Policy.self_approval_allowed?(nil, @staging)
      refute Policy.self_approval_allowed?(@engineer, nil)
      refute Policy.self_approval_allowed?(nil, nil)
    end
  end

  describe "admin_emails/0" do
    test "matches the hardcoded list" do
      assert Enum.sort(Policy.admin_emails()) == Enum.sort(@founders)
    end
  end
end
