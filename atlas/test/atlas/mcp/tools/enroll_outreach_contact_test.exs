defmodule Atlas.MCP.Tools.EnrollOutreachContactTest do
  use Atlas.MCP.ToolCase

  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.OpportunityContact
  alias Atlas.MCP.Tools.EnrollOutreachContact

  test "enrolls an Apollo suggestion and returns its new account contact" do
    user = insert_user!()

    opportunity =
      %Opportunity{}
      |> Opportunity.changeset(%{
        company_key: "domain:tool-enrollment.example",
        company_name: "Tool Enrollment",
        domain: "tool-enrollment.example",
        score: 80
      })
      |> Repo.insert!()

    suggestion =
      %OpportunityContact{opportunity_id: opportunity.id}
      |> OpportunityContact.changeset(%{
        source: "apollo",
        full_name: "Priya Raman",
        title: "Head of Platform Engineering",
        linkedin_url: "https://www.linkedin.com/in/priya-raman",
        confidence: 91,
        metadata: %{"apollo_id" => "apollo-priya"}
      })
      |> Repo.insert!()

    assert {:ok, payload} =
             execute_tool(EnrollOutreachContact, mcp_conn(user), %{
               "opportunity_contact_id" => suggestion.id
             })

    assert payload.full_name == "Priya Raman"
    assert payload.account_name == "Tool Enrollment"
    assert [%{kind: "enrolled"}] = payload.events
  end
end
