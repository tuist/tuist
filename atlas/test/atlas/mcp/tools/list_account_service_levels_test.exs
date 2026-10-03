defmodule Atlas.MCP.Tools.ListAccountServiceLevelsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tools.ListAccountServiceLevels

  test "lists extracted service levels for an account" do
    account = insert_account!(%{account_key: "service-level-acct", name: "Service Level Account"})
    document = insert_document!(account, %{title: "Service Level Account SLA"})
    check = insert_check!(account, document)

    service_level =
      insert_service_level!(account, document, check, %{
        name: "Monthly uptime",
        category: "availability",
        target: "99.9% monthly uptime",
        target_value: Decimal.new("99.9"),
        target_unit: "percent",
        applies_from: ~D[2026-01-01],
        applies_until: ~D[2026-12-31],
        source_page: 2,
        source_excerpt: "Monthly uptime will be at least 99.9%."
      })

    assert {:ok, payload} =
             execute_tool(ListAccountServiceLevels, nil, %{"account_key" => "service-level-acct"})

    assert payload.account.name == "Service Level Account"
    assert payload.count == 1
    assert [%{id: id, name: "Monthly uptime"} = result] = payload.service_levels
    assert id == service_level.id
    assert result.document_title == "Service Level Account SLA"
    assert result.document_url =~ "/documents/#{document.id}/download/service-level-account-sla.txt"
    assert result.target_value == "99.9"
    assert result.applies_until == "2026-12-31"
    assert [%{id: check_id, status: "completed"}] = payload.service_level_extraction_checks
    assert check_id == check.id
  end

  test "filters service levels by active date" do
    account = insert_account!(%{account_key: "active-service-level"})
    document = insert_document!(account, %{})
    check = insert_check!(account, document)

    active =
      insert_service_level!(account, document, check, %{
        name: "Active uptime",
        target: "99.9% uptime",
        applies_from: ~D[2026-01-01],
        applies_until: ~D[2026-12-31]
      })

    _expired =
      insert_service_level!(account, document, check, %{
        name: "Expired uptime",
        target: "99.5% uptime",
        applies_from: ~D[2025-01-01],
        applies_until: ~D[2025-12-31]
      })

    assert {:ok, payload} =
             execute_tool(ListAccountServiceLevels, nil, %{
               "account_key" => "active-service-level",
               "active_on" => "2026-06-01"
             })

    assert [%{id: id}] = payload.service_levels
    assert id == active.id
  end

  test "rejects invalid active_on dates" do
    account = insert_account!(%{account_key: "bad-active-date"})

    assert {:error, "active_on must be a YYYY-MM-DD date."} =
             execute_tool(ListAccountServiceLevels, nil, %{
               "account_id" => account.id,
               "active_on" => "tomorrow"
             })
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

  defp insert_check!(account, document) do
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
