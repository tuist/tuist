defmodule Atlas.MCP.Tools.FeatureInterestToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreateFeatureInterest
  alias Atlas.MCP.Tools.GetFeatureInterest
  alias Atlas.MCP.Tools.ListAccountFeatureInterests
  alias Atlas.MCP.Tools.ListFeatureInterests
  alias Atlas.MCP.Tools.RecordFeatureInterest
  alias Atlas.MCP.Tools.UpdateFeatureInterestAccountContext

  test "creates a capability before it has account evidence" do
    title = "Build capacity planning #{System.unique_integer([:positive])}"

    assert {:ok, created} =
             execute_tool(CreateFeatureInterest, executive_mcp_conn(), %{"title" => title})

    assert created.title == title
    assert created.status == "open"
    assert created.interest_count == 0
    assert is_nil(created.last_interested_at)
  end

  test "records a request from timeline evidence and returns the account record through the tool surface" do
    account = insert_account!(%{name: "Feature request account"})
    event = insert_event!(account, %{kind: "meeting", source: "granola"})
    conn = executive_mcp_conn()

    assert {:ok, created} =
             execute_tool(RecordFeatureInterest, conn, %{
               "account_id" => account.id,
               "account_event_id" => event.id,
               "title" => "Remote build runners",
               "summary" => "They need managed runners for their release builds.",
               "context" => "Release capacity is the immediate concern."
             })

    assert created.title == "Remote build runners"
    assert created.interest_count == 1

    assert {:ok, %{feature_interests: [listed]}} = execute_tool(ListFeatureInterests, conn, %{})
    assert listed.id == created.id

    assert {:ok, detail} =
             execute_tool(GetFeatureInterest, conn, %{"feature_interest_id" => created.id})

    assert [interest_account] = detail.accounts
    assert interest_account.account_id == account.id
    assert interest_account.account_event_id == event.id
    assert interest_account.notes == "Release capacity is the immediate concern."
    assert interest_account.context == "Release capacity is the immediate concern."

    assert {:ok, %{feature_interests: [account_interest]}} =
             execute_tool(ListAccountFeatureInterests, conn, %{"account_id" => account.id})

    assert account_interest.id == interest_account.id
    assert account_interest.account_event_path == "/commercial/sales/accounts/#{account.id}#timeline-event-#{event.id}"
  end

  test "updates account-specific context through the tool surface" do
    account = insert_account!()
    event = insert_event!(account)
    conn = executive_mcp_conn()

    assert {:ok, _created} =
             execute_tool(RecordFeatureInterest, conn, %{
               "account_id" => account.id,
               "account_event_id" => event.id,
               "title" => "Remote build runners",
               "summary" => "They need managed runners for their release builds."
             })

    assert {:ok, %{feature_interests: [interest_account]}} =
             execute_tool(ListAccountFeatureInterests, conn, %{"account_id" => account.id})

    assert {:ok, updated} =
             execute_tool(UpdateFeatureInterestAccountContext, conn, %{
               "feature_interest_account_id" => interest_account.id,
               "context" => "Pilot this with the release engineering group."
             })

    assert updated.notes == "Pilot this with the release engineering group."
    assert updated.context == "Pilot this with the release engineering group."
  end

  test "does not record a request against an event linked to another account" do
    account = insert_account!()
    other_account = insert_account!()
    event = insert_event!(other_account)

    assert {:error, "Timeline event is not linked to the specified account"} =
             execute_tool(RecordFeatureInterest, executive_mcp_conn(), %{
               "account_id" => account.id,
               "account_event_id" => event.id,
               "title" => "Remote build runners",
               "summary" => "They need managed runners for their release builds."
             })
  end
end
