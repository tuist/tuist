defmodule Atlas.Coordination.Claims do
  @moduledoc """
  Persists versioned claims only when their cross-domain links are precise.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.Coordination.CrossDomainClaim
  alias Atlas.Evidence
  alias Atlas.Links
  alias Atlas.Product.Trace
  alias Atlas.Repo

  def list_current(opts \\ []) do
    CrossDomainClaim
    |> where([claim], is_nil(claim.superseded_by_id))
    |> maybe_filter_account(Keyword.get(opts, :account_id))
    |> maybe_filter_kind(Keyword.get(opts, :claim_kind))
    |> order_by([claim], desc: claim.valid_from, desc: claim.id)
    |> preload(:subject_account)
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    CrossDomainClaim
    |> preload(:subject_account)
    |> Repo.get(id)
  end

  def create(%Account{} = account, attrs, evidence, opts \\ []) when is_map(attrs) and is_list(evidence) do
    attrs = stringify_keys(attrs)

    with {:ok, precision, basis} <- validate_links(account, attrs, evidence, opts),
         :ok <- validate_domains(attrs, evidence) do
      Repo.transaction(fn -> persist_claim(account, attrs, evidence, precision, basis, opts) end)
    end
  end

  defp persist_claim(account, attrs, evidence, precision, basis, opts) do
    lock_account!(account.id)
    current = lock_current(account.id, attrs["claim_kind"])

    if current && current.statement == attrs["statement"] do
      current
    else
      insert_claim(account, attrs, evidence, precision, basis, current, opts)
    end
  end

  defp insert_claim(account, attrs, evidence, precision, basis, current, opts) do
    now = utc_now()

    claim =
      %CrossDomainClaim{subject_account_id: account.id}
      |> CrossDomainClaim.changeset(
        attrs
        |> Map.put("version", next_version(current))
        |> Map.put("link_precision", to_string(precision))
        |> Map.put("link_basis", basis)
        |> Map.put_new("valid_from", now)
      )
      |> Repo.insert!()

    link_evidence!(claim, evidence)
    supersede(current, claim, now)
    audit_claim(claim, opts)
    claim
  end

  defp link_evidence!(claim, evidence) do
    case Evidence.link_all("cross_domain_claim", claim.id, evidence) do
      {:ok, _links} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp supersede(nil, _claim, _now), do: :ok

  defp supersede(current, claim, now) do
    current
    |> Ecto.Changeset.change(%{superseded_by_id: claim.id, valid_until: now})
    |> Repo.update!()
  end

  defp next_version(nil), do: 1
  defp next_version(current), do: current.version + 1

  defp validate_links(account, %{"claim_kind" => "account_delivery_dependency"} = attrs, evidence, opts) do
    actor = Keyword.get(opts, :actor)
    account_event = Enum.find(evidence, &(value(&1, :record_type) == "account_event"))
    product_trace = Enum.find(evidence, &(value(&1, :record_type) == "product_trace"))

    with actor when not is_nil(actor) <- actor,
         event when not is_nil(event) <- account_event,
         trace when not is_nil(trace) <- product_trace,
         {:exact, linked_account, event_basis} <-
           Links.resolve_account("account_event", value(event, :record_id)),
         true <- linked_account.id == account.id,
         %Trace{} = product <- Repo.get(Trace, value(trace, :record_id)),
         true <- account_event_references_product?(event, product),
         basis when is_binary(basis) and basis != "" <- attrs["link_basis"] do
      {:ok, :verified, "#{event_basis}; #{basis}"}
    else
      _invalid -> {:error, :verified_cross_domain_link_required}
    end
  end

  defp validate_links(account, _attrs, evidence, _opts) do
    results =
      Enum.map(evidence, fn item ->
        Links.resolve_account(value(item, :record_type), value(item, :record_id))
      end)

    if results != [] and
         Enum.all?(results, fn
           {:exact, linked_account, _basis} -> linked_account.id == account.id
           _result -> false
         end) do
      basis = results |> Enum.map(fn {:exact, _account, basis} -> basis end) |> Enum.uniq() |> Enum.join("; ")
      {:ok, :exact, basis}
    else
      {:error, :exact_cross_domain_link_required}
    end
  end

  defp validate_domains(%{"domains" => domains}, evidence) when is_list(domains) do
    evidence_domains = evidence |> MapSet.new(&evidence_domain/1)
    declared_domains = MapSet.new(domains)

    if MapSet.size(declared_domains) >= 2 and MapSet.subset?(declared_domains, evidence_domains),
      do: :ok,
      else: {:error, :cross_domain_evidence_required}
  end

  defp validate_domains(_attrs, _evidence), do: {:error, :cross_domain_evidence_required}

  defp evidence_domain(item) do
    case value(item, :record_type) do
      "account_term" -> "finance"
      "outreach_message_attempt" -> "outreach"
      "product_trace" -> "product"
      "finance_invoice" -> "finance"
      "finance_transaction" -> "finance"
      _record_type -> "accounts"
    end
  end

  defp account_event_references_product?(event_evidence, product) do
    case Atlas.Repo.get(Event, value(event_evidence, :record_id)) do
      %Event{body: body} when is_binary(body) -> String.contains?(body, product.url)
      _event -> false
    end
  end

  defp lock_current(account_id, claim_kind) do
    CrossDomainClaim
    |> where(
      [claim],
      claim.subject_account_id == ^account_id and claim.claim_kind == ^claim_kind and
        is_nil(claim.superseded_by_id)
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp lock_account!(account_id) do
    Account
    |> where([account], account.id == ^account_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp maybe_filter_account(query, nil), do: query
  defp maybe_filter_account(query, account_id), do: where(query, [claim], claim.subject_account_id == ^account_id)
  defp maybe_filter_kind(query, nil), do: query
  defp maybe_filter_kind(query, kind), do: where(query, [claim], claim.claim_kind == ^kind)

  defp audit_claim(claim, opts) do
    Audit.record(
      "cross_domain_claim.created",
      %{
        target_type: "cross_domain_claim",
        target_id: claim.id,
        target_label: claim.statement,
        metadata: %{
          "account_id" => claim.subject_account_id,
          "claim_kind" => claim.claim_kind,
          "domains" => claim.domains,
          "link_precision" => claim.link_precision
        }
      },
      opts
    )
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
