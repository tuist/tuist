defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners
  alias Tuist.Runners.RunnerAssignment

  describe "create_pre_bound_assignment/1" do
    test "persists pool + jit + owner at create time" do
      attrs = %{
        pod_uid: "pod-uid-pb-1",
        pod_name: "tuist-runner-tuist-abcd",
        pool_name: "tuist",
        jit_config: "encoded-jit-payload",
        dispatch_token_hash: Runners.hash_token("token-pb"),
        owner: "tuist"
      }

      assert {:ok, %RunnerAssignment{} = a} = Runners.create_pre_bound_assignment(attrs)
      assert a.pool_name == "tuist"
      assert a.jit_config == "encoded-jit-payload"
      assert a.owner == "tuist"
      assert a.repo == nil
    end

    test "rejects when required fields missing" do
      attrs = %{
        pod_uid: "pod-uid-pb-2",
        pod_name: "n",
        dispatch_token_hash: Runners.hash_token("t")
      }

      assert {:error, %Ecto.Changeset{}} = Runners.create_pre_bound_assignment(attrs)
    end

    test "rejects duplicate pod_uid" do
      attrs = %{
        pod_uid: "pod-uid-pb-dup",
        pod_name: "n",
        pool_name: "tuist",
        jit_config: "j",
        dispatch_token_hash: Runners.hash_token("t"),
        owner: "tuist"
      }

      {:ok, _} = Runners.create_pre_bound_assignment(attrs)
      assert {:error, %Ecto.Changeset{}} = Runners.create_pre_bound_assignment(attrs)
    end
  end

  describe "delete_assignment/1" do
    test "removes the row by pod_uid" do
      {:ok, _} =
        Runners.create_pre_bound_assignment(%{
          pod_uid: "pod-uid-del",
          pod_name: "n",
          pool_name: "tuist",
          jit_config: "j",
          dispatch_token_hash: Runners.hash_token("t"),
          owner: "tuist"
        })

      assert :ok = Runners.delete_assignment("pod-uid-del")
      assert Runners.get_assignment("pod-uid-del") == nil
    end

    test "is idempotent for missing rows" do
      assert :ok = Runners.delete_assignment("pod-uid-missing")
    end
  end

  describe "claim_assignment/1" do
    test "stamps claimed_at on first claim, no-ops on second" do
      {:ok, assignment} =
        Runners.create_pre_bound_assignment(%{
          pod_uid: "pod-uid-c",
          pod_name: "n",
          pool_name: "tuist",
          jit_config: "j",
          dispatch_token_hash: Runners.hash_token("t"),
          owner: "tuist"
        })

      assert assignment.claimed_at == nil
      assert {:ok, claimed} = Runners.claim_assignment(assignment)
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
