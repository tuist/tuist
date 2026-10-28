defmodule Atlas.MCP.Tools.ListAccountIncidentContactsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tools.ListAccountIncidentContacts

  test "lists security-incident contacts extracted from an account document" do
    account_key = "incident-contacts-#{System.unique_integer([:positive])}"
    account = insert_account!(%{account_key: account_key, name: "Incident Contact Account"})
    document = insert_document!(account)
    check = insert_check!(account, document)

    contact =
      %IncidentContact{
        account_id: account.id,
        document_id: document.id,
        service_level_extraction_check_id: check.id
      }
      |> IncidentContact.changeset(%{
        email: "security@example.com",
        full_name: "Security Operations",
        role: "Security incident notifications",
        source_page: 3,
        source_excerpt: "Notify security@example.com after a security incident.",
        confidence: "0.98"
      })
      |> Repo.insert!()

    assert {:ok, payload} =
             execute_tool(ListAccountIncidentContacts, nil, %{"account_key" => account.account_key})

    assert payload.account.id == account.id
    assert payload.count == 1
    assert [%{id: id, email: "security@example.com"} = listed] = payload.incident_contacts
    assert id == contact.id
    assert listed.document_title == "Incident contacts"
    assert listed.document_url =~ "/documents/#{document.id}/download/incident-contacts.txt"
    assert listed.confidence == "0.98"
  end

  defp insert_document!(account) do
    unique = System.unique_integer([:positive])

    %Document{}
    |> Document.changeset(%{
      title: "Incident contacts",
      original_filename: "incident-contacts.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "incident-contacts-#{unique}",
      storage_bucket: "test-documents",
      storage_key: "documents/incident-contacts-#{unique}.txt",
      status: "ready",
      source: "upload"
    })
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.insert!()
  end

  defp insert_check!(account, document) do
    %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
    |> ServiceLevelExtractionCheck.changeset(%{
      agent_version: "service_level_extraction_agent:v2",
      document_checksum_sha256: document.checksum_sha256,
      status: "completed",
      started_at: ~U[2026-08-24 00:00:00Z],
      completed_at: ~U[2026-08-24 00:01:00Z]
    })
    |> Repo.insert!()
  end
end
