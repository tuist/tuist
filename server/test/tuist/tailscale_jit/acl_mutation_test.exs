defmodule Tuist.TailscaleJIT.ACLMutationTest do
  use ExUnit.Case, async: true

  alias Tuist.TailscaleJIT.ACLMutation

  @fixture_path Path.join([__DIR__, "..", "..", "fixtures", "tailscale_jit", "acl_baseline.hujson"])

  setup do
    {:ok, doc: File.read!(@fixture_path)}
  end

  describe "list_members/2" do
    test "lists members of a populated group", %{doc: doc} do
      assert {:ok, ["pedro@tuist.dev", "marek@tuist.dev"]} =
               ACLMutation.list_members(doc, "group:tuist-admins")
    end

    test "lists empty group as []", %{doc: doc} do
      assert {:ok, []} = ACLMutation.list_members(doc, "group:tuist-prod-write")
    end

    test "errors on unknown group", %{doc: doc} do
      assert {:error, :group_not_found} = ACLMutation.list_members(doc, "group:does-not-exist")
    end
  end

  describe "add_member/3" do
    test "adds to an empty group and preserves everything else byte-for-byte", %{doc: doc} do
      assert {:ok, new_doc} = ACLMutation.add_member(doc, "group:tuist-prod-write", "alice@tuist.dev")

      # The targeted array changed.
      assert new_doc =~ ~s("group:tuist-prod-write":    ["alice@tuist.dev"])
      # Everything else identical.
      assert difference_outside_group(doc, new_doc, "group:tuist-prod-write") == ""
    end

    test "is idempotent: adding the same member twice yields the same document", %{doc: doc} do
      {:ok, once} = ACLMutation.add_member(doc, "group:tuist-prod-write", "alice@tuist.dev")
      {:ok, twice} = ACLMutation.add_member(once, "group:tuist-prod-write", "alice@tuist.dev")
      assert once == twice
    end

    test "preserves existing members and appends the new one", %{doc: doc} do
      assert {:ok, new_doc} = ACLMutation.add_member(doc, "group:tuist-admins", "alice@tuist.dev")

      assert {:ok, members} = ACLMutation.list_members(new_doc, "group:tuist-admins")
      assert members == ["pedro@tuist.dev", "marek@tuist.dev", "alice@tuist.dev"]
    end

    test "errors on unknown group without touching the document", %{doc: doc} do
      assert {:error, :group_not_found} =
               ACLMutation.add_member(doc, "group:nope", "alice@tuist.dev")
    end
  end

  describe "remove_member/3" do
    test "removes an existing member", %{doc: doc} do
      assert {:ok, new_doc} = ACLMutation.remove_member(doc, "group:tuist-admins", "marek@tuist.dev")
      assert {:ok, ["pedro@tuist.dev"]} = ACLMutation.list_members(new_doc, "group:tuist-admins")
    end

    test "no-op success when member is absent", %{doc: doc} do
      assert {:ok, new_doc} = ACLMutation.remove_member(doc, "group:tuist-admins", "ghost@tuist.dev")
      assert new_doc == doc
    end

    test "leaves the empty array shape intact when removing the last member", %{doc: doc} do
      assert {:ok, after_add} = ACLMutation.add_member(doc, "group:tuist-prod-write", "alice@tuist.dev")
      assert {:ok, after_remove} = ACLMutation.remove_member(after_add, "group:tuist-prod-write", "alice@tuist.dev")
      assert {:ok, []} = ACLMutation.list_members(after_remove, "group:tuist-prod-write")
    end
  end

  describe "round-trip stability" do
    test "add then remove returns the document to its original form for a previously-empty group", %{doc: doc} do
      assert {:ok, after_add} = ACLMutation.add_member(doc, "group:tuist-prod-write", "alice@tuist.dev")
      assert {:ok, after_remove} = ACLMutation.remove_member(after_add, "group:tuist-prod-write", "alice@tuist.dev")
      assert after_remove == doc
    end

    test "comments and unrelated keys survive a mutation", %{doc: doc} do
      assert {:ok, new_doc} = ACLMutation.add_member(doc, "group:tuist-canary-write", "alice@tuist.dev")

      # Comments inside the groups block.
      assert new_doc =~ "// Founders."
      assert new_doc =~ "// Break-glass groups (empty by default)."
      # Comments in unrelated sections.
      assert new_doc =~ "// Comment in grants."
      # Unrelated group untouched.
      assert new_doc =~ ~s("group:tuist-admins": ["pedro@tuist.dev", "marek@tuist.dev"])
      # tagOwners block untouched.
      assert new_doc =~ ~s("tag:tuist-k8s-production": ["autogroup:admin"])
      # grants block untouched.
      assert new_doc =~ ~s({"src": ["*"], "dst": ["*"], "ip": ["*"]})
    end
  end

  # Returns the diff between two documents after blanking out the
  # targeted group's array; if the splice was clean, this returns "".
  defp difference_outside_group(doc_a, doc_b, group_name) do
    pattern = ~r/"#{Regex.escape(group_name)}"\s*:\s*\[[^\]]*\]/
    blanked_a = Regex.replace(pattern, doc_a, "<<elided>>")
    blanked_b = Regex.replace(pattern, doc_b, "<<elided>>")
    if blanked_a == blanked_b, do: "", else: "documents differ outside the targeted group"
  end
end
