defmodule Atlas.MCP.Tools.GetAccountTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Accounts.Term
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tools.GetAccount

  test "resolves by account_id and bundles contract, contact, and event context" do
    parent = insert_account!(%{name: "Acme Holdings", account_key: "acme-holdings"})

    account =
      insert_account!(%{
        name: "Acme",
        legal_name: "Acme, Inc.",
        contract_id: "Acme-0726",
        hosting: "self_hosted",
        account_key: "acme-bundle",
        parent_account_id: parent.id,
        address: %{street: "123 Market Street", city: "San Francisco", zip: "94105", country: "US"},
        billing: %{email: "billing@acme.io", sold_to: "Acme, Inc.", vat_id: "US-123"},
        signatory: %{name: "Alice Example", title: "Chief Executive Officer"}
      })

    child = insert_account!(%{name: "Acme Labs", account_key: "acme-labs", parent_account_id: account.id})
    insert_contact!(account, %{full_name: "Alice", email: "alice@acme.io"})
    _event = insert_event!(account, %{title: "Kickoff", kind: "meeting"})
    insert_handle!(account, %{handle: "#acme", source: "slack"})

    %Term{account_id: account.id}
    |> Term.changeset(%{
      source: "manual",
      payment: "monthly",
      start_date: ~D[2026-08-01],
      end_date: ~D[2027-07-31],
      price_per_seat: Decimal.new("50"),
      seats: 35,
      total: Decimal.new("21000"),
      currency: "USD",
      on_premise: false
    })
    |> Repo.insert!()

    {:ok, payload} = execute_tool(GetAccount, nil, %{"account_id" => account.id})

    assert payload.account.name == "Acme"
    assert payload.account.legal_name == "Acme, Inc."
    assert payload.account.contract_id == "Acme-0726"
    assert payload.account.hosting == "self_hosted"
    assert payload.account.address.city == "San Francisco"
    assert payload.account.billing.email == "billing@acme.io"
    assert payload.account.signatory.name == "Alice Example"
    assert payload.account.parent_account.name == "Acme Holdings"
    assert [%{id: child_id, name: "Acme Labs"}] = payload.account.child_accounts
    assert child_id == child.id
    assert [%{full_name: "Alice"}] = payload.contacts
    assert [%{title: "Kickoff"}] = payload.recent_events
    assert [%{handle: "#acme"}] = payload.handles
    assert [%{seats: 35, price_per_seat: "50", on_premise: false}] = payload.terms
  end

  test "bundles service levels and recent extraction checks" do
    account = insert_account!(%{name: "Service Bundle", account_key: "service-bundle"})
    document = insert_document!(account, %{title: "Service Bundle SLA"})
    check = insert_service_level_extraction_check!(account, document)

    service_level =
      insert_service_level!(account, document, check, %{
        name: "Monthly uptime",
        category: "availability",
        target: "99.9% monthly uptime",
        target_value: Decimal.new("99.9"),
        target_unit: "percent",
        source_page: 2
      })

    {:ok, payload} = execute_tool(GetAccount, nil, %{"account_id" => account.id})

    assert [%{id: service_level_id, document_title: "Service Bundle SLA"} = result] = payload.service_levels
    assert service_level_id == service_level.id
    assert result.target_value == "99.9"
    assert result.document_url =~ "/documents/#{document.id}/download/service-bundle-sla.txt"

    assert [%{id: check_id, status: "completed", document_title: "Service Bundle SLA"}] =
             payload.service_level_extraction_checks

    assert check_id == check.id
  end

  test "resolves by handle" do
    account = insert_account!(%{name: "Acme", account_key: "acme-handle"})
    insert_handle!(account, %{handle: "#acme-team", source: "slack"})

    {:ok, payload} = execute_tool(GetAccount, nil, %{"handle" => "#acme-team"})

    assert payload.account.id == account.id
  end

  test "returns an error when no identifier is provided" do
    assert {:error, "Provide one of account_id, account_key, or handle."} =
             execute_tool(GetAccount, nil, %{})
  end

  test "returns an error when the account is missing" do
    assert {:error, "Account not found for account_key: nope"} =
             execute_tool(GetAccount, nil, %{"account_key" => "nope"})
  end

  defp insert_document!(account, attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.insert!()
  end

  defp insert_service_level_extraction_check!(account, document) do
    %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
    |> ServiceLevelExtractionCheck.changeset(%{
      agent_version: "service_level_extraction_agent:v1",
      document_checksum_sha256: document.checksum_sha256,
      status: "completed",
      started_at: ~U[2026-06-01 00:00:00Z],
      completed_at: ~U[2026-06-01 00:01:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_service_level!(account, document, check, attrs) do
    defaults = %{
      name: "Availability",
      category: "availability",
      target: "99.9% uptime"
    }

    %ServiceLevel{
      account_id: account.id,
      document_id: document.id,
      service_level_extraction_check_id: check.id
    }
    |> ServiceLevel.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
