defmodule Atlas.AuditTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Users.User

  test "records actor, interface, changed fields, and dashboard path from context operations" do
    user = insert_user!(%{email: "auditor@example.com", name: "Auditor"})

    {:ok, account} =
      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        Accounts.create_account(%{
          account_key: "audit:account",
          name: "Audit Account",
          segment: :prospect
        })
      end)

    activity = Repo.get_by!(Activity, action: "account.created")

    assert activity.actor_id == user.id
    assert activity.actor_email == "auditor@example.com"
    assert activity.actor_name == "Auditor"
    assert activity.interface == "dashboard"
    assert activity.target_type == "account"
    assert activity.target_id == account.id
    assert activity.target_label == "Audit Account"
    assert activity.metadata["path"] == "/commercial/sales/accounts/#{account.id}"
    assert activity.metadata["changed"]["name"] == "Audit Account"
  end

  test "normalizes string-keyed attrs and serializes dashboard paths" do
    assert {:ok, activity} =
             Audit.log("document.uploaded", %{
               "interface" => "mcp",
               "target_type" => "document",
               "target_id" => "document-id",
               "target_label" => "Document",
               "metadata" => %{"source" => "test"}
             })

    assert activity.interface == "mcp"
    assert activity.metadata["source"] == "test"
    assert activity.metadata["path"] == "/library/documents/document-id"

    assert Audit.serialize(activity).target.path == "/library/documents/document-id"
  end

  test "merges context metadata into recorded activity metadata" do
    Audit.with_context(%{interface: "slack", metadata: %{"agent_identity_key" => "leadership"}}, fn ->
      Audit.record("test.action", %{
        target_type: "test",
        target_id: "target-id",
        metadata: %{"status" => "ok"}
      })
    end)

    activity = Repo.get_by!(Activity, action: "test.action")

    assert activity.metadata["agent_identity_key"] == "leadership"
    assert activity.metadata["status"] == "ok"
  end

  test "does not invent dashboard paths for resources without dashboard surfaces" do
    assert is_nil(Audit.resource_path("brief", "brief-id"))
    assert is_nil(Audit.resource_path("brief_item", "item-id", %{"brief_id" => "brief-id"}))
    assert is_nil(Audit.resource_path("product_trace", "trace-id"))
  end

  test "extracts audit metadata from agent claims" do
    assert Audit.claim_metadata(%{
             "agent_identity_key" => "leadership",
             "slack_channel_id" => "C_LEADERSHIP",
             "unrelated" => "ignored"
           }) == %{
             "agent_identity_key" => "leadership",
             "slack_channel_id" => "C_LEADERSHIP"
           }
  end

  test "filters activities with pagination metadata" do
    {:ok, _activity} =
      Audit.log("account.updated", %{
        interface: "dashboard",
        actor_email: "alice@example.com",
        target_type: "account",
        target_id: "account-1"
      })

    {:ok, _activity} =
      Audit.log("blog_post_idea.created", %{
        interface: "slack",
        actor_email: "bob@example.com",
        target_type: "blog_post_idea",
        target_id: "idea-1"
      })

    {activities, meta} = Audit.list_activities(interface: "slack", query: "bob", page_size: 1)

    assert Enum.map(activities, & &1.action) == ["blog_post_idea.created"]
    assert meta.current_page == 1
    assert meta.page_size == 1
    assert meta.total_count == 1
    refute meta.has_next_page?

    {activities, _meta} = Audit.list_activities(exclude_interface: "dashboard")

    assert Enum.map(activities, & &1.action) == ["blog_post_idea.created"]
  end

  defp insert_user!(attrs) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
