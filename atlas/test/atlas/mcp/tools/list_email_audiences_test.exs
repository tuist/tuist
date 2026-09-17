defmodule Atlas.MCP.Tools.ListEmailAudiencesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM
  alias Atlas.MCP.Tools.CreateEmailAudience
  alias Atlas.MCP.Tools.ListEmailAudiences

  test "lists audiences with their counts" do
    user = insert_user!()
    {:ok, audience} = GTM.create_email_audience(%{name: "MCP Digest"})

    assert {:ok, %{audiences: [listed], count: 1}} = execute_tool(ListEmailAudiences, conn_for(user), %{})
    assert listed.id == audience.id
    assert listed.name == "MCP Digest"
  end

  test "returns an empty list when there are no audiences" do
    user = insert_user!()

    assert {:ok, %{audiences: [], count: 0}} = execute_tool(ListEmailAudiences, conn_for(user), %{})
  end

  test "creates and lists a dynamic account-contact audience" do
    user = insert_user!()

    assert {:ok, %{audience: created}} =
             execute_tool(CreateEmailAudience, conn_for(user), %{
               "name" => "Enterprise accounts #{System.unique_integer([:positive])}",
               "membership_type" => "dynamic",
               "rules" => %{"account_segment" => "customer", "hosting" => "self_hosted"}
             })

    assert created.membership_type == "dynamic"

    assert created.rules == %{
             "account_segment" => "customer",
             "contacts_per_account" => "all",
             "hosting" => "self_hosted",
             "recipient_source" => "account_contacts"
           }

    assert {:ok, %{audiences: [listed], count: 1}} = execute_tool(ListEmailAudiences, conn_for(user), %{})
    assert listed.id == created.id
    assert listed.membership_type == "dynamic"
  end
end
