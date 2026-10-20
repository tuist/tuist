defmodule Atlas.Accounts.ServiceLevelsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.ServiceLevelExtractionAgent
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Audit.Activity
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage

  setup :verify_on_exit!

  describe "ServiceLevel.changeset/2" do
    test "validates category, source page, and confidence bounds" do
      changeset =
        %ServiceLevel{
          account_id: Ecto.UUID.generate(),
          document_id: Ecto.UUID.generate(),
          service_level_extraction_check_id: Ecto.UUID.generate()
        }
        |> ServiceLevel.changeset(%{
          name: "Latency",
          category: "latency",
          target: "60 ms",
          source_page: 0,
          confidence: "1.2"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).category
      assert Map.has_key?(errors_on(changeset), :source_page)
      assert Map.has_key?(errors_on(changeset), :confidence)
    end
  end

  describe "ServiceLevelExtractionCheck.changeset/2" do
    test "validates status values" do
      changeset =
        %ServiceLevelExtractionCheck{
          account_id: Ecto.UUID.generate(),
          document_id: Ecto.UUID.generate()
        }
        |> ServiceLevelExtractionCheck.changeset(%{
          agent_version: "service_level_extraction_agent:v2",
          document_checksum_sha256: "checksum",
          status: "skipped"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "IncidentContact.changeset/2" do
    test "normalizes the email and validates its format" do
      changeset =
        %IncidentContact{
          account_id: Ecto.UUID.generate(),
          document_id: Ecto.UUID.generate(),
          service_level_extraction_check_id: Ecto.UUID.generate()
        }
        |> IncidentContact.changeset(%{email: "  INCIDENT@Example.com "})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :email) == "incident@example.com"

      invalid = IncidentContact.changeset(%IncidentContact{}, %{email: "not-an-email"})
      refute invalid.valid?
      assert "has invalid format" in errors_on(invalid).email
    end
  end

  describe "extract_document_service_levels/2" do
    test "persists extracted service levels and the extraction check" do
      account = insert_account!(%{name: "Acme", segment: :customer})
      document = insert_document!(account, %{title: "Acme SLA"})
      insert_page!(document, "Service Level Agreement. Monthly uptime will be at least 99.9%.")

      expect(ServiceLevelExtractionAgent, :extract, fn extracted_document ->
        assert extracted_document.id == document.id
        assert extracted_document.account.id == account.id

        {:ok,
         %{
           "summary" => "Availability service level extracted.",
           "service_levels" => [
             %{
               "name" => "Monthly availability",
               "category" => "availability",
               "target" => "99.9% monthly uptime",
               "target_value" => "99.9",
               "target_unit" => "percent",
               "measurement_window" => "monthly",
               "applies_from" => "2026-01-01",
               "applies_until" => "2026-12-31",
               "service_credit" => "Service credits apply below target.",
               "source_page" => 1,
               "source_excerpt" => "Monthly uptime will be at least 99.9%.",
               "confidence" => "0.93"
             }
           ]
         }}
      end)

      assert {:ok, %{status: :completed, check: check, service_levels: [service_level]}} =
               Accounts.extract_document_service_levels(document.id)

      assert check.status == "completed"
      assert check.result_summary == "Availability service level extracted."
      assert check.document_checksum_sha256 == document.checksum_sha256

      assert service_level.account_id == account.id
      assert service_level.document_id == document.id
      assert service_level.service_level_extraction_check_id == check.id
      assert service_level.category == "availability"
      assert service_level.target == "99.9% monthly uptime"
      assert Decimal.equal?(service_level.target_value, Decimal.new("99.9"))
      assert Decimal.equal?(service_level.confidence, Decimal.new("0.93"))
      assert service_level.applies_from == ~D[2026-01-01]
      assert service_level.applies_until == ~D[2026-12-31]

      activity = Repo.get_by!(Activity, action: "account_service_levels.extracted", target_id: account.id)
      assert activity.metadata["service_levels_count"] == 1
    end

    test "records no_service_level_found and skips a document that was already checked" do
      account = insert_account!(%{name: "No SLA", segment: :customer})
      document = insert_document!(account, %{title: "Order Form"})
      insert_page!(document, "Commercial order form with no service levels.")

      expect(ServiceLevelExtractionAgent, :extract, fn _document -> {:ok, %{"service_levels" => []}} end)

      assert {:ok, %{status: :no_service_level_found, check: check, service_levels: []}} =
               Accounts.extract_document_service_levels(document.id)

      assert check.status == "no_service_level_found"

      activity = Repo.get_by!(Activity, action: "account_service_levels.none_found", target_id: account.id)
      assert activity.metadata["service_levels_count"] == 0
      assert activity.metadata["incident_contacts_count"] == 0

      assert {:ok, %{status: :already_checked, service_levels: []}} =
               Accounts.extract_document_service_levels(document.id)
    end

    test "normalizes model null placeholders before persisting service levels" do
      account = insert_account!(%{name: "Null Placeholders", segment: :customer})
      document = insert_document!(account, %{title: "Placeholder SLA"})
      insert_page!(document, "Monthly uptime will be at least 99.9%.")

      expect(ServiceLevelExtractionAgent, :extract, fn _document ->
        {:ok,
         %{
           "summary" => "nil",
           "service_levels" => [
             %{
               "name" => "Monthly availability",
               "category" => "availability",
               "target" => "99.9% monthly uptime",
               "target_unit" => "nil",
               "measurement_window" => "N/A",
               "service_credit" => "none",
               "exclusions" => "null",
               "source_excerpt" => "Monthly uptime will be at least 99.9%."
             }
           ]
         }}
      end)

      assert {:ok, %{status: :completed, check: check, service_levels: [service_level]}} =
               Accounts.extract_document_service_levels(document.id)

      assert is_nil(check.result_summary)
      assert is_nil(service_level.target_unit)
      assert is_nil(service_level.measurement_window)
      assert is_nil(service_level.service_credit)
      assert is_nil(service_level.exclusions)
    end

    test "persists security-incident contacts from the contract evidence" do
      account = insert_account!(%{name: "Incident Contacts"})
      document = insert_document!(account, %{title: "Incident notification addendum"})
      insert_page!(document, "Notify security@example.com after a security incident.")

      expect(ServiceLevelExtractionAgent, :extract, fn _document ->
        {:ok,
         %{
           "service_levels" => [],
           "incident_contacts" => [
             %{
               "email" => " SECURITY@example.com ",
               "full_name" => "Security Operations",
               "role" => "Security incident notifications",
               "source_page" => 1,
               "source_excerpt" => "Notify security@example.com after a security incident.",
               "confidence" => "0.98"
             }
           ]
         }}
      end)

      assert {:ok, %{status: :completed, incident_contacts: [contact]}} =
               Accounts.extract_document_service_levels(document.id)

      assert contact.email == "security@example.com"
      assert contact.account_id == account.id
      assert contact.document_id == document.id
      assert contact.role == "Security incident notifications"
      assert Decimal.equal?(contact.confidence, Decimal.new("0.98"))

      assert [listed] = Accounts.list_incident_contacts(account)
      assert listed.id == contact.id
      assert listed.document.title == "Incident notification addendum"

      activity = Repo.get_by!(Activity, action: "account_incident_contacts.extracted")
      assert activity.target_id == account.id
      assert activity.metadata["incident_contacts_count"] == 1
    end

    test "candidate documents exclude completed checks for the same document checksum" do
      account = insert_account!(%{name: "Candidates", segment: :customer})
      checked = insert_document!(account, %{title: "Checked SLA"})
      unchecked = insert_document!(account, %{title: "Unchecked SLA"})
      insert_page!(checked, "SLA")
      insert_page!(unchecked, "SLA")

      expect(ServiceLevelExtractionAgent, :extract, fn _document -> {:ok, %{"service_levels" => []}} end)

      assert {:ok, %{status: :no_service_level_found}} =
               Accounts.extract_document_service_levels(checked.id)

      assert Accounts.list_service_level_candidate_document_ids() == [unchecked.id]
    end

    test "refreshes a stale processing check with the current document checksum" do
      account = insert_account!(%{name: "Stale Check", segment: :customer})
      document = insert_document!(account, %{title: "Updated SLA"})
      insert_page!(document, "Service Level Agreement.")

      stale_check =
        %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
        |> ServiceLevelExtractionCheck.changeset(%{
          agent_version: "service_level_extraction_agent:v2",
          document_checksum_sha256: "old-checksum",
          status: "processing",
          started_at: ~U[2026-06-01 00:00:00Z]
        })
        |> Repo.insert!()

      expect(ServiceLevelExtractionAgent, :extract, fn _document -> {:ok, %{"service_levels" => []}} end)

      assert {:ok, %{status: :no_service_level_found, check: check}} =
               Accounts.extract_document_service_levels(document.id)

      assert check.id == stale_check.id
      assert check.document_checksum_sha256 == document.checksum_sha256
      assert check.status == "no_service_level_found"
      assert Accounts.list_service_level_candidate_document_ids() == []
    end

    test "returns an error for account documents without extracted pages" do
      account = insert_account!(%{name: "No Pages", segment: :customer})
      document = insert_document!(account, %{title: "Empty"})

      assert {:error, :document_has_no_pages} = Accounts.extract_document_service_levels(document.id)
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
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

  defp insert_page!(document, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{
      document_id: document.id,
      page_number: 1,
      content: content
    })
    |> Repo.insert!()
  end
end
