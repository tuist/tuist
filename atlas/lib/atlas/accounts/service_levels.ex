defmodule Atlas.Accounts.ServiceLevels do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.ServiceLevelExtractionAgent
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Repo

  require Logger

  @agent_version "service_level_extraction_agent:v2"
  @completed_check_statuses ~w(completed no_service_level_found)
  @default_candidate_limit 25

  def agent_version, do: @agent_version

  def list_service_levels(account_or_id, opts \\ [])

  def list_service_levels(%Account{id: account_id}, opts) do
    list_service_levels(account_id, opts)
  end

  def list_service_levels(account_id, opts) when is_binary(account_id) do
    active_on = Keyword.get(opts, :active_on)

    ServiceLevel
    |> where([service_level], service_level.account_id == ^account_id)
    |> maybe_filter_active_on(active_on)
    |> order_by([service_level],
      asc: service_level.category,
      asc_nulls_last: service_level.applies_until,
      asc: service_level.name
    )
    |> preload([:document, :extraction_check])
    |> Repo.all()
  end

  def list_service_level_extraction_checks(account_or_id, opts \\ [])

  def list_service_level_extraction_checks(%Account{id: account_id}, opts) do
    list_service_level_extraction_checks(account_id, opts)
  end

  def list_service_level_extraction_checks(account_id, opts) when is_binary(account_id) do
    limit = Keyword.get(opts, :limit, 10)

    ServiceLevelExtractionCheck
    |> where([check], check.account_id == ^account_id)
    |> order_by([check], desc: check.started_at, desc: check.inserted_at)
    |> limit(^limit)
    |> preload(:document)
    |> Repo.all()
  end

  def list_incident_contacts(account_or_id)

  def list_incident_contacts(%Account{id: account_id}) do
    list_incident_contacts(account_id)
  end

  def list_incident_contacts(account_id) when is_binary(account_id) do
    IncidentContact
    |> where([contact], contact.account_id == ^account_id)
    |> order_by([contact], asc: contact.email, asc: contact.inserted_at)
    |> preload([:document, :extraction_check])
    |> Repo.all()
  end

  def list_service_level_candidate_document_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_candidate_limit)
    agent_version = Keyword.get(opts, :agent_version, @agent_version)

    Document
    |> where([document], document.status == "ready")
    |> where([document], not is_nil(document.account_id))
    |> join(:left, [document], check in ServiceLevelExtractionCheck,
      on:
        check.document_id == document.id and check.agent_version == ^agent_version and
          check.document_checksum_sha256 == document.checksum_sha256 and
          check.status in ^@completed_check_statuses
    )
    |> where([_document, check], is_nil(check.id))
    |> order_by([document], asc_nulls_last: document.document_date, asc: document.inserted_at, asc: document.id)
    |> limit(^limit)
    |> select([document], document.id)
    |> Repo.all()
  end

  def extract_document_service_levels(document_id, opts \\ []) when is_binary(document_id) do
    force? = Keyword.get(opts, :force?, false)
    agent_version = Keyword.get(opts, :agent_version, @agent_version)

    with %Document{} = document <- get_ready_account_document(document_id),
         :ok <- ensure_document_extractable(document),
         {:ok, check} <- prepare_check(document, agent_version, force?) do
      if completed_for_current_document?(check, document, agent_version) and not force? do
        {:ok,
         %{
           status: :already_checked,
           check: check,
           service_levels: list_check_service_levels(check),
           incident_contacts: list_check_incident_contacts(check)
         }}
      else
        run_extraction(document, check)
      end
    else
      nil -> {:error, :document_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_ready_account_document(document_id) do
    Document
    |> where([document], document.id == ^document_id)
    |> preload([
      :account,
      :document_type,
      :correspondent,
      :tags,
      pages: ^from(page in DocumentPage, order_by: [asc: page.page_number])
    ])
    |> Repo.one()
  end

  defp ensure_document_extractable(%Document{status: status}) when status != "ready" do
    {:error, :document_not_ready}
  end

  defp ensure_document_extractable(%Document{account_id: nil}), do: {:error, :account_not_found}
  defp ensure_document_extractable(%Document{pages: []}), do: {:error, :document_has_no_pages}
  defp ensure_document_extractable(%Document{}), do: :ok

  defp prepare_check(%Document{} = document, agent_version, force?) do
    now = utc_now()

    case Repo.get_by(ServiceLevelExtractionCheck, document_id: document.id, agent_version: agent_version) do
      %ServiceLevelExtractionCheck{} = check when not force? ->
        {:ok, check}

      %ServiceLevelExtractionCheck{} = check ->
        update_processing_check(check, document, agent_version, now)

      nil ->
        %ServiceLevelExtractionCheck{account_id: document.account_id, document_id: document.id}
        |> ServiceLevelExtractionCheck.changeset(%{
          agent_version: agent_version,
          document_checksum_sha256: document.checksum_sha256,
          status: "processing",
          started_at: now,
          completed_at: nil,
          last_error: nil
        })
        |> Repo.insert()
    end
  end

  defp completed_for_current_document?(%ServiceLevelExtractionCheck{} = check, %Document{} = document, agent_version) do
    check.agent_version == agent_version and check.document_checksum_sha256 == document.checksum_sha256 and
      check.status in @completed_check_statuses
  end

  defp run_extraction(%Document{} = document, %ServiceLevelExtractionCheck{} = check) do
    check = update_processing_check!(check, document, check.agent_version, utc_now())

    case ServiceLevelExtractionAgent.extract(document) do
      {:ok, result} ->
        case persist_extraction_result(document, check, result) do
          {:ok, %{incident_contacts: incident_contacts} = extraction} = outcome ->
            audit_service_level_extraction(document, extraction)

            if incident_contacts != [] do
              audit_incident_contact_extraction(document, incident_contacts)
            end

            outcome

          outcome ->
            outcome
        end

      {:error, reason} ->
        {:ok, failed} = mark_check_failed(check, reason)
        audit_service_level_extraction_failure(document, failed)
        {:error, %{reason: reason, check: failed}}
    end
  end

  defp update_processing_check(check, document, agent_version, now) do
    check
    |> ServiceLevelExtractionCheck.changeset(%{
      agent_version: agent_version,
      document_checksum_sha256: document.checksum_sha256,
      status: "processing",
      started_at: now,
      completed_at: nil,
      last_error: nil,
      result_summary: nil
    })
    |> Repo.update()
  end

  defp update_processing_check!(check, document, agent_version, now) do
    {:ok, check} = update_processing_check(check, document, agent_version, now)
    check
  end

  defp persist_extraction_result(document, check, result) do
    normalized = normalize_extraction_result(result)
    now = utc_now()

    Repo.transaction(fn ->
      from(service_level in ServiceLevel, where: service_level.service_level_extraction_check_id == ^check.id)
      |> Repo.delete_all()

      from(contact in IncidentContact, where: contact.service_level_extraction_check_id == ^check.id)
      |> Repo.delete_all()

      service_levels =
        normalized.service_levels
        |> Enum.map(fn service_level_attrs ->
          %ServiceLevel{
            account_id: document.account_id,
            document_id: document.id,
            service_level_extraction_check_id: check.id
          }
          |> ServiceLevel.changeset(service_level_attrs)
          |> Repo.insert!()
        end)

      incident_contacts =
        normalized.incident_contacts
        |> Enum.map(fn contact_attrs ->
          %IncidentContact{
            account_id: document.account_id,
            document_id: document.id,
            service_level_extraction_check_id: check.id
          }
          |> IncidentContact.changeset(contact_attrs)
          |> Repo.insert!()
        end)

      result_status = if service_levels == [] and incident_contacts == [], do: :no_service_level_found, else: :completed
      check_status = Atom.to_string(result_status)

      updated_check =
        check
        |> ServiceLevelExtractionCheck.changeset(%{
          status: check_status,
          completed_at: now,
          last_error: nil,
          result_summary: normalized.summary,
          metadata: normalized.metadata
        })
        |> Repo.update!()

      %{
        status: result_status,
        check: updated_check,
        service_levels: service_levels,
        incident_contacts: incident_contacts
      }
    end)
  rescue
    error ->
      Logger.error(
        "Failed to persist service level extraction for document #{document.id}: #{Exception.message(error)}"
      )

      {:ok, failed} = mark_check_failed(check, error)
      {:error, %{reason: error, check: failed}}
  end

  defp mark_check_failed(check, reason) do
    check
    |> ServiceLevelExtractionCheck.changeset(%{
      status: "failed",
      completed_at: utc_now(),
      last_error: inspect(reason)
    })
    |> Repo.update()
  end

  defp list_check_service_levels(%ServiceLevelExtractionCheck{id: check_id}) do
    ServiceLevel
    |> where([service_level], service_level.service_level_extraction_check_id == ^check_id)
    |> order_by([service_level], asc: service_level.category, asc: service_level.name)
    |> preload([:document, :extraction_check])
    |> Repo.all()
  end

  defp list_check_incident_contacts(%ServiceLevelExtractionCheck{id: check_id}) do
    IncidentContact
    |> where([contact], contact.service_level_extraction_check_id == ^check_id)
    |> order_by([contact], asc: contact.email)
    |> preload([:document, :extraction_check])
    |> Repo.all()
  end

  defp normalize_extraction_result(result) when is_map(result) do
    service_levels =
      result
      |> fetch_any(["service_levels", :service_levels], [])
      |> normalize_service_levels()

    incident_contacts =
      result
      |> fetch_any(["incident_contacts", :incident_contacts], [])
      |> normalize_incident_contacts()

    %{
      summary: clean_string(fetch_any(result, ["summary", :summary])),
      metadata: clean_map(fetch_any(result, ["metadata", :metadata], %{})),
      service_levels: service_levels,
      incident_contacts: incident_contacts
    }
  end

  defp normalize_extraction_result(_result),
    do: %{summary: nil, metadata: %{}, service_levels: [], incident_contacts: []}

  defp normalize_service_levels(values) when is_list(values) do
    values
    |> Enum.map(&normalize_service_level/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_service_levels(_values), do: []

  defp normalize_service_level(value) when is_map(value) do
    target = clean_string(fetch_any(value, ["target", :target]))

    if !is_nil(target) do
      category = normalize_category(fetch_any(value, ["category", :category]))

      %{
        name:
          clean_string(fetch_any(value, ["name", :name, "title", :title])) ||
            default_service_level_name(category),
        category: category,
        target: target,
        target_value: decimal_value(fetch_any(value, ["target_value", :target_value])),
        target_unit: clean_string(fetch_any(value, ["target_unit", :target_unit])),
        measurement_window: clean_string(fetch_any(value, ["measurement_window", :measurement_window])),
        applies_from: date_value(fetch_any(value, ["applies_from", :applies_from])),
        applies_until: date_value(fetch_any(value, ["applies_until", :applies_until])),
        service_credit: clean_string(fetch_any(value, ["service_credit", :service_credit])),
        exclusions: clean_string(fetch_any(value, ["exclusions", :exclusions])),
        source_page: positive_integer(fetch_any(value, ["source_page", :source_page])),
        source_excerpt: clean_string(fetch_any(value, ["source_excerpt", :source_excerpt])),
        confidence: decimal_value(fetch_any(value, ["confidence", :confidence])),
        metadata: clean_map(fetch_any(value, ["metadata", :metadata], %{}))
      }
    end
  end

  defp normalize_service_level(_value), do: nil

  defp normalize_incident_contacts(values) when is_list(values) do
    values
    |> Enum.map(&normalize_incident_contact/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&String.downcase(&1.email))
  end

  defp normalize_incident_contacts(_values), do: []

  defp normalize_incident_contact(value) when is_map(value) do
    email = clean_email(fetch_any(value, ["email", :email]))

    if email do
      %{
        email: email,
        full_name: clean_string(fetch_any(value, ["full_name", :full_name, "name", :name])),
        role: clean_string(fetch_any(value, ["role", :role])),
        source_page: positive_integer(fetch_any(value, ["source_page", :source_page])),
        source_excerpt: clean_string(fetch_any(value, ["source_excerpt", :source_excerpt])),
        confidence: decimal_value(fetch_any(value, ["confidence", :confidence])),
        metadata: clean_map(fetch_any(value, ["metadata", :metadata], %{}))
      }
    end
  end

  defp normalize_incident_contact(_value), do: nil

  defp fetch_any(map, keys, default \\ nil) do
    Enum.find_value(keys, default, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp normalize_category(value) do
    value =
      value
      |> clean_string()
      |> case do
        nil -> "other"
        category -> category |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_") |> String.trim("_")
      end

    if value in ServiceLevel.categories(), do: value, else: "other"
  end

  defp default_service_level_name("availability"), do: "Availability"
  defp default_service_level_name("response_time"), do: "Response time"
  defp default_service_level_name("resolution_time"), do: "Resolution time"
  defp default_service_level_name("support_hours"), do: "Support hours"
  defp default_service_level_name("maintenance"), do: "Maintenance"
  defp default_service_level_name("backup"), do: "Backup"
  defp default_service_level_name("data_retention"), do: "Data retention"
  defp default_service_level_name("security"), do: "Security"
  defp default_service_level_name(_category), do: "Service level"

  defp clean_string(value) when is_binary(value) do
    value = String.trim(value)

    case String.downcase(value) do
      "" -> nil
      "nil" -> nil
      "null" -> nil
      "none" -> nil
      "n/a" -> nil
      "not applicable" -> nil
      "not specified" -> nil
      _value -> value
    end
  end

  defp clean_string(value) when is_atom(value), do: value |> Atom.to_string() |> clean_string()
  defp clean_string(_value), do: nil

  defp clean_email(value) when is_binary(value) do
    email = value |> String.trim() |> String.downcase()
    if String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/), do: email
  end

  defp clean_email(_value), do: nil

  defp clean_map(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {to_string(key), value} end)
  end

  defp clean_map(_value), do: %{}

  defp date_value(%Date{} = date), do: date

  defp date_value(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date_value(_value), do: nil

  defp decimal_value(%Decimal{} = decimal), do: decimal
  defp decimal_value(value) when is_integer(value), do: Decimal.new(value)
  defp decimal_value(value) when is_float(value), do: Decimal.from_float(value)

  defp decimal_value(value) when is_binary(value) do
    case Regex.run(~r/-?\d+(?:\.\d+)?/, value) do
      [number] -> Decimal.new(number)
      _match -> nil
    end
  rescue
    _error -> nil
  end

  defp decimal_value(_value), do: nil

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp maybe_filter_active_on(query, nil), do: query

  defp maybe_filter_active_on(query, %Date{} = date) do
    where(
      query,
      [service_level],
      (is_nil(service_level.applies_from) or service_level.applies_from <= ^date) and
        (is_nil(service_level.applies_until) or service_level.applies_until >= ^date)
    )
  end

  defp audit_incident_contact_extraction(document, incident_contacts) do
    Audit.record("account_incident_contacts.extracted", %{
      target_type: "account",
      target_id: document.account_id,
      target_label: document.account.name,
      metadata: %{
        account_path: "/sales/accounts/#{document.account_id}",
        document_id: document.id,
        document_path: "/documents/#{document.id}",
        incident_contacts_count: length(incident_contacts)
      }
    })
  end

  defp audit_service_level_extraction(document, outcome) do
    action =
      if outcome.status == :no_service_level_found do
        "account_service_levels.none_found"
      else
        "account_service_levels.extracted"
      end

    Audit.record(action, %{
      target_type: "account",
      target_id: document.account_id,
      target_label: document.account.name,
      metadata: %{
        "path" => "/sales/accounts/#{document.account_id}",
        "document_id" => document.id,
        "document_path" => "/documents/#{document.id}",
        "extraction_check_id" => outcome.check.id,
        "status" => Atom.to_string(outcome.status),
        "service_levels_count" => length(outcome.service_levels),
        "incident_contacts_count" => length(outcome.incident_contacts)
      }
    })
  end

  defp audit_service_level_extraction_failure(document, check) do
    Audit.record("account_service_levels.extraction_failed", %{
      target_type: "account",
      target_id: document.account_id,
      target_label: document.account.name,
      metadata: %{
        "path" => "/sales/accounts/#{document.account_id}",
        "document_id" => document.id,
        "document_path" => "/documents/#{document.id}",
        "extraction_check_id" => check.id
      }
    })
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
