defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners
  alias Tuist.Runners.RunnerAssignment

  describe "create_idle_assignment/1" do
    test "persists pod_uid + token hash with NULL pool/jit/owner/repo" do
      attrs = %{
        pod_uid: "pod-uid-1",
        pod_name: "tuist-runner-abcd",
        dispatch_token_hash: Runners.hash_token("token-1")
      }

      assert {:ok, %RunnerAssignment{} = a} = Runners.create_idle_assignment(attrs)
      assert a.pod_uid == "pod-uid-1"
      assert a.jit_config == nil
      assert a.pool_name == nil
      assert RunnerAssignment.idle?(a)
    end

    test "rejects duplicate pod_uid" do
      attrs = %{
        pod_uid: "pod-uid-2",
        pod_name: "n",
        dispatch_token_hash: Runners.hash_token("t")
      }

      {:ok, _} = Runners.create_idle_assignment(attrs)
      assert {:error, %Ecto.Changeset{}} = Runners.create_idle_assignment(attrs)
    end
  end

  describe "create_pre_bound_assignment/1" do
    test "persists pool + jit + owner/repo at create time (not idle)" do
      attrs = %{
        pod_uid: "pod-uid-pb-1",
        pod_name: "tuist-runner-tuist-tuist-abcd",
        pool_name: "tuist-tuist",
        jit_config: "encoded-jit-payload",
        dispatch_token_hash: Runners.hash_token("token-pb"),
        owner: "tuist",
        repo: "tuist"
      }

      assert {:ok, %RunnerAssignment{} = a} = Runners.create_pre_bound_assignment(attrs)
      assert a.pool_name == "tuist-tuist"
      assert a.jit_config == "encoded-jit-payload"
      refute RunnerAssignment.idle?(a)
    end

    test "rejects when required fields missing" do
      attrs = %{
        pod_uid: "pod-uid-pb-2",
        pod_name: "n",
        dispatch_token_hash: Runners.hash_token("t")
      }

      assert {:error, %Ecto.Changeset{}} = Runners.create_pre_bound_assignment(attrs)
    end
  end

  describe "list_idle_assignments/0" do
    test "returns only shared rows (jit_config IS NULL); pre-bound ones are excluded" do
      {:ok, _shared} =
        Runners.create_idle_assignment(%{
          pod_uid: "pod-uid-list-shared",
          pod_name: "shared",
          dispatch_token_hash: Runners.hash_token("t")
        })

      {:ok, _pre_bound} =
        Runners.create_pre_bound_assignment(%{
          pod_uid: "pod-uid-list-pre-bound",
          pod_name: "pre-bound",
          pool_name: "tuist-tuist",
          jit_config: "j",
          dispatch_token_hash: Runners.hash_token("t2"),
          owner: "tuist",
          repo: "tuist"
        })

      idle_uids = Enum.map(Runners.list_idle_assignments(), & &1.pod_uid)
      assert "pod-uid-list-shared" in idle_uids
      refute "pod-uid-list-pre-bound" in idle_uids
    end
  end

  describe "dispatch_assignment/2" do
    setup do
      {:ok, idle} =
        Runners.create_idle_assignment(%{
          pod_uid: "pod-uid-d",
          pod_name: "n",
          dispatch_token_hash: Runners.hash_token("t")
        })

      %{idle: idle}
    end

    test "fills in jit + pool + owner/repo", %{idle: idle} do
      assert {:ok, dispatched} =
               Runners.dispatch_assignment(idle, %{
                 pool_name: "tuist-tuist",
                 jit_config: "encoded-jit",
                 owner: "tuist",
                 repo: "tuist"
               })

      refute RunnerAssignment.idle?(dispatched)
      assert dispatched.pool_name == "tuist-tuist"
      assert dispatched.jit_config == "encoded-jit"
    end
  end

  describe "claim_assignment/1" do
    test "stamps claimed_at on first claim, no-ops on second" do
      {:ok, idle} =
        Runners.create_idle_assignment(%{
          pod_uid: "pod-uid-c",
          pod_name: "n",
          dispatch_token_hash: Runners.hash_token("t")
        })

      {:ok, dispatched} =
        Runners.dispatch_assignment(idle, %{
          pool_name: "p",
          jit_config: "j",
          owner: "o",
          repo: "r"
        })

      assert dispatched.claimed_at == nil
      assert {:ok, claimed} = Runners.claim_assignment(dispatched)
      assert claimed.claimed_at

      assert {:ok, claimed_again} = Runners.claim_assignment(claimed)
      assert claimed_again.claimed_at == claimed.claimed_at
    end
  end

  describe "token_matches?/2" do
    test "matches the original token, rejects others" do
      token = "secret-token"
      hash = Runners.hash_token(token)
      assignment = %RunnerAssignment{dispatch_token_hash: hash}

      assert Runners.token_matches?(assignment, token)
      refute Runners.token_matches?(assignment, "different-token")
    end
  end
end
