defmodule Atlas.Accounts do
  @moduledoc """
  Public account context boundary.

  This module keeps the stable API used by LiveViews, workers, and ingestion
  pipelines while focused modules own account queries, revenue snapshots,
  overview summaries, and Stripe invoice reconciliation.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.ContractValue
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.EventRouting
  alias Atlas.Accounts.FeatureInterests
  alias Atlas.Accounts.HandleRegistry
  alias Atlas.Accounts.Invoices
  alias Atlas.Accounts.OrderForms
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposals
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.OverviewSummary
  alias Atlas.Accounts.Query
  alias Atlas.Accounts.Revenue
  alias Atlas.Accounts.ServiceLevels
  alias Atlas.Accounts.Term
  alias Atlas.Accounts.Workers.GenerateOutcomeProposals
  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Repo
  alias Atlas.Search

  defdelegate list_accounts(opts \\ []), to: Query
  defdelegate list_account_ids(), to: Query
  defdelegate list_overview_summary_candidate_ids(opts \\ []), to: Query
  defdelegate list_outcome_review_candidate_ids(opts \\ []), to: Query
  defdelegate list_outcome_proposal_candidate_ids(opts \\ []), to: Query
  defdelegate list_parent_account_options(account_id \\ nil), to: Query
  defdelegate list_stripe_customer_account_ids(), to: Query
  defdelegate list_attention_outcomes(opts \\ []), to: Query
  defdelegate list_outcome_review_accounts(opts \\ []), to: Query
  defdelegate list_outcome_review_updates(opts \\ []), to: Query
  defdelegate list_upcoming_renewals(opts \\ []), to: Query
  defdelegate sales_overview_counts(today \\ Date.utc_today()), to: Query
  defdelegate account_filters(), to: Query
  defdelegate account_counts(), to: Query
  defdelegate list_outcome_proposals(account_or_id, opts \\ []), to: OutcomeProposals, as: :list
  defdelegate get_outcome_proposal(id), to: OutcomeProposals, as: :get
  defdelegate get_outcome_proposal(account, id), to: OutcomeProposals, as: :get
  defdelegate change_outcome_proposal(proposal, attrs \\ %{}), to: OutcomeProposals, as: :change
  defdelegate create_outcome_proposal(account, attrs), to: OutcomeProposals, as: :create
  defdelegate update_outcome_proposal(proposal, attrs, actor \\ nil), to: OutcomeProposals, as: :update
  defdelegate reject_outcome_proposal(proposal, reason, actor \\ nil), to: OutcomeProposals, as: :reject
  defdelegate approve_outcome_proposal(proposal, actor \\ nil), to: OutcomeProposals, as: :approve
  defdelegate generate_outcome_proposals(account_id), to: OutcomeProposals, as: :generate
  defdelegate get_account(id), to: Query
  defdelegate revenue_snapshot(opts \\ []), to: Revenue, as: :snapshot
  defdelegate stripe_invoices(account, opts \\ []), to: Invoices
  defdelegate sales_overview_invoices(opts \\ []), to: Invoices
  defdelegate outstanding_invoices_summary(today \\ Date.utc_today()), to: Invoices
  defdelegate create_stripe_draft_invoice_from_latest_signed_order_form(account_or_id, opts \\ []), to: Invoices

  defdelegate edit_stripe_draft_invoice(account_or_id, invoice_id, edit_attrs \\ %{}, opts \\ []), to: Invoices

  defdelegate reconcile_stripe_invoices(account), to: Invoices
  defdelegate reconciled_stripe_invoices(account), to: Invoices
  defdelegate refresh_overview_summary(account_id, opts \\ []), to: OverviewSummary, as: :refresh
  defdelegate list_service_levels(account_or_id, opts \\ []), to: ServiceLevels
  defdelegate list_service_level_extraction_checks(account_or_id, opts \\ []), to: ServiceLevels
  defdelegate list_incident_contacts(account_or_id), to: ServiceLevels
  defdelegate list_service_level_candidate_document_ids(opts \\ []), to: ServiceLevels
  defdelegate extract_document_service_levels(document_id, opts \\ []), to: ServiceLevels
  defdelegate list_feature_interests(), to: FeatureInterests, as: :list
  defdelegate get_feature_interest(id), to: FeatureInterests, as: :get
  defdelegate change_feature_interest_definition(attrs \\ %{}), to: FeatureInterests, as: :change_definition
  defdelegate create_feature_interest(attrs, actor \\ nil), to: FeatureInterests, as: :create_definition
  defdelegate list_feature_interests_for_account(account_or_id), to: FeatureInterests, as: :list_for_account
  defdelegate get_feature_interest_account(id), to: FeatureInterests, as: :get_account_interest
  defdelegate get_account_event(account_or_id, event_id), to: FeatureInterests

  defdelegate record_feature_interest_from_event(event, attrs, actor \\ nil),
    to: FeatureInterests,
    as: :record_from_event

  defdelegate change_feature_interest(attrs \\ %{}), to: FeatureInterests, as: :change_account_interest

  defdelegate change_feature_interest_notes(interest_account, attrs \\ %{}),
    to: FeatureInterests,
    as: :change_account_interest_notes

  defdelegate update_feature_interest_notes(interest_account, attrs, actor \\ nil),
    to: FeatureInterests,
    as: :update_notes

  def upcoming_invoices(account, today \\ Date.utc_today()) do
    Invoices.upcoming_invoices(account, today)
  end

  def contract_value(account, today \\ Date.utc_today()) do
    ContractValue.value(account, today)
  end

  def contract_value_source(account, today \\ Date.utc_today()) do
    ContractValue.source(account, today)
  end

  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.edit_changeset(account, attrs)
  end

  def change_manual_account(attrs \\ %{}) when is_map(attrs) do
    %Account{account_key: "manual:preview", segment: :prospect}
    |> Account.manual_changeset(attrs)
  end

  def get_account_by_name(name) when is_binary(name) do
    Account
    |> where([account], fragment("lower(?) = ?", account.name, ^String.downcase(name)))
    |> where([account], is_nil(account.not_an_account_at))
    |> order_by([account], asc: account.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      %Account{} = account -> {:ok, account}
    end
  end

  def get_account_by_name(_name), do: {:error, :not_found}

  def create_account(attrs) when is_map(attrs) do
    changeset = Account.changeset(%Account{}, attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, account} -> audit_account("account.created", account, changeset)
      _result -> :ok
    end)
  end

  # How many times we retry a manual insert when a concurrent creation wins the
  # unique account_key race between picking a free key and inserting.
  @manual_account_key_attempts 5

  def create_manual_account(attrs) when is_map(attrs) do
    # Sentinel normalization (""/"_none" -> nil) and slug rules are shared with
    # edit_changeset and EventRouting respectively, so this only owns picking a
    # free account_key and inserting.
    base = "manual:#{manual_account_slug(attrs)}"
    insert_manual_account(attrs, base, @manual_account_key_attempts)
  end

  defp insert_manual_account(attrs, base, attempts_left) do
    changeset =
      %Account{account_key: next_available_account_key(base), segment: :prospect}
      |> Account.manual_changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, account} = result ->
        audit_account("account.created", account, changeset)
        result

      {:error, error_changeset} = result ->
        if attempts_left > 1 and account_key_conflict?(error_changeset) do
          insert_manual_account(attrs, base, attempts_left - 1)
        else
          result
        end
    end
  end

  # Resolves the next free key for `base` in a single query: fetch the keys that
  # already occupy `base`/`base-N`, then pick the lowest unused suffix.
  defp next_available_account_key(base) do
    taken =
      Account
      |> where([account], account.account_key == ^base or like(account.account_key, ^"#{base}-%"))
      |> select([account], account.account_key)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.member?(taken, base) do
      Stream.iterate(2, &(&1 + 1))
      |> Stream.map(&"#{base}-#{&1}")
      |> Enum.find(&(not MapSet.member?(taken, &1)))
    else
      base
    end
  end

  defp account_key_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:account_key, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _other -> false
    end)
  end

  defp manual_account_slug(attrs) do
    attrs
    |> manual_account_key_source()
    |> String.replace(~r/^https?:\/\//i, "")
    |> String.replace(~r/^www\./i, "")
    |> EventRouting.slugify()
  end

  defp manual_account_key_source(attrs) do
    first_present([
      manual_account_attr(attrs, "primary_domain", :primary_domain),
      manual_account_attr(attrs, "name", :name)
    ]) || "account"
  end

  defp manual_account_attr(attrs, string_key, atom_key) do
    Map.get(attrs, string_key) || Map.get(attrs, atom_key)
  end

  def update_account(%Account{} = account, attrs) when is_map(attrs) do
    changeset =
      account
      |> Account.edit_changeset(attrs)
      |> reject_parent_account_cycle(account)

    handle_snapshot_relevant_change? = handle_snapshot_relevant_change?(changeset)

    case Repo.update(changeset) do
      {:ok, updated} = result ->
        audit_account("account.updated", updated, changeset)

        if handle_snapshot_relevant_change?,
          do: broadcast_account_snapshot_change(updated)

        result

      error ->
        error
    end
  end

  # Fields the HandleRegistry snapshot copies out of accounts. Any change
  # to one of these needs a broadcast so nodes rewrite their cached
  # entries; a change outside this list is invisible to the registry.
  defp handle_snapshot_relevant_change?(changeset) do
    Enum.any?([:name, :primary_domain, :plan_tier, :account_key], &Map.has_key?(changeset.changes, &1))
  end

  defp broadcast_account_snapshot_change(%Account{} = account) do
    HandleRegistry.broadcast_change(%{
      action: :account_updated,
      account_id: account.id,
      entry: %{
        account_key: account.account_key,
        name: account.name,
        primary_domain: account.primary_domain,
        plan_tier: account.plan_tier
      }
    })
  end

  @doc """
  Updates an account's commercial fields from a signed order form.

  Authoritative fields (`currency`, `current_value`, `next_renewal_date`,
  `segment`) overwrite the existing values; softer fields (`deal_stage`,
  `poc_end_date`) fill blanks only. Returns `:noop` when the document is not
  a signed order form, has no account, or has no extractable fields.

  Pages may be passed explicitly when the document's `pages` association is
  not preloaded (the ingest pipeline calls in with freshly inserted pages
  before they are reloaded).
  """
  def sync_account_from_order_form(document, pages \\ nil)

  def sync_account_from_order_form(%Document{account_id: nil}, _pages), do: :noop

  def sync_account_from_order_form(%Document{} = document, pages) do
    with true <- OrderForms.signed?(document, pages),
         %Account{} = account <- Repo.get(Account, document.account_id),
         attrs when map_size(attrs) > 0 <- OrderForms.commercial_attrs(document, account) do
      update_account(account, attrs)
    else
      _other -> :noop
    end
  end

  def mark_account_not_account(%Account{} = account, attrs \\ %{}) when is_map(attrs) do
    changeset = Account.not_account_changeset(account, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_account("account.marked_not_account", updated, changeset)
      _result -> :ok
    end)
  end

  def mark_outcome_review_company_slack_posted(account_or_id, posted_at \\ utc_now())

  def mark_outcome_review_company_slack_posted(%Account{} = account, %DateTime{} = posted_at) do
    changeset =
      Account.outcome_review_changeset(account, %{
        outcome_review_company_slack_posted_at: DateTime.truncate(posted_at, :second)
      })

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_account("account.outcome_review_slack_marked", updated, changeset)
      _result -> :ok
    end)
  end

  def mark_outcome_review_company_slack_posted(account_id, %DateTime{} = posted_at) when is_binary(account_id) do
    case Repo.get(Account, account_id) do
      nil -> {:error, :not_found}
      account -> mark_outcome_review_company_slack_posted(account, posted_at)
    end
  end

  defp reject_parent_account_cycle(changeset, %Account{id: account_id}) do
    parent_account_id = Ecto.Changeset.get_field(changeset, :parent_account_id)

    if parent_account_id && parent_chain_contains?(parent_account_id, account_id) do
      Ecto.Changeset.add_error(changeset, :parent_account_id, "can't be a child account")
    else
      changeset
    end
  end

  defp parent_chain_contains?(account_id, target_id, visited \\ MapSet.new())

  defp parent_chain_contains?(nil, _target_id, _visited), do: false

  defp parent_chain_contains?(account_id, target_id, visited) do
    cond do
      account_id == target_id ->
        true

      MapSet.member?(visited, account_id) ->
        false

      true ->
        case Repo.get(Account, account_id) do
          nil -> false
          account -> parent_chain_contains?(account.parent_account_id, target_id, MapSet.put(visited, account_id))
        end
    end
  end

  def delete_account(%Account{} = account) do
    account
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:licenses, message: "still has associated licenses")
    |> Repo.delete(allow_stale: true)
    |> tap(fn
      {:ok, deleted} -> audit_account("account.deleted", deleted, %{})
      _result -> :ok
    end)
  end

  def change_contact(%Account{} = account), do: change_contact(account, %{})
  def change_contact(%Contact{} = contact), do: change_contact(contact, %{})

  def change_contact(%Account{} = account, attrs) when is_map(attrs) do
    %Contact{account_id: account.id}
    |> Contact.edit_changeset(attrs)
  end

  def change_contact(%Contact{} = contact, attrs) when is_map(attrs) do
    Contact.edit_changeset(contact, attrs)
  end

  def create_contact(%Account{} = account, attrs) when is_map(attrs) do
    changeset =
      %Contact{account_id: account.id}
      |> Contact.edit_changeset(attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, contact} ->
        refresh_contact_count(contact.account_id)
        audit_contact("contact.created", contact, changeset)

      _result ->
        :ok
    end)
  end

  def update_contact(%Contact{} = contact, attrs) when is_map(attrs) do
    changeset = Contact.edit_changeset(contact, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_contact("contact.updated", updated, changeset)
      _result -> :ok
    end)
  end

  def delete_contact(%Contact{} = contact) do
    contact
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} ->
        refresh_contact_count(deleted.account_id)
        audit_contact("contact.deleted", deleted, %{})

      _result ->
        :ok
    end)
  end

  def change_note(%Account{} = account, attrs \\ %{}, author \\ nil) do
    %Event{}
    |> Event.changeset(note_params(account, attrs, author))
    |> Ecto.Changeset.validate_required([:body])
  end

  def create_note(%Account{} = account, attrs, author \\ nil) when is_map(attrs) do
    changeset =
      %Event{}
      |> Event.changeset(note_params(account, attrs, author))
      |> Ecto.Changeset.validate_required([:body])

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, event} ->
        Search.index_account_event(event)
        audit_event("account_note.created", event, changeset, actor: author)

      _result ->
        :ok
    end)
  end

  def enqueue_outcome_proposal_generation(account_id, source \\ "system") when is_binary(account_id) do
    %{account_id: account_id, source: source}
    |> GenerateOutcomeProposals.new(
      unique: [
        period: {6, :hour},
        fields: [:worker, :args],
        keys: [:account_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
    |> Oban.insert()
  end

  def list_outcomes(account_or_id, opts \\ [])

  def list_outcomes(%Account{id: account_id}, opts), do: list_outcomes(account_id, opts)

  def list_outcomes(account_id, opts) when is_binary(account_id) do
    statuses = Keyword.get(opts, :statuses)

    Outcome
    |> where([outcome], outcome.account_id == ^account_id)
    |> maybe_filter_outcome_statuses(statuses)
    |> order_by([outcome],
      asc:
        fragment(
          "CASE ? WHEN 'active' THEN 0 WHEN 'achieved' THEN 1 WHEN 'missed' THEN 2 ELSE 3 END",
          outcome.status
        ),
      asc:
        fragment(
          "CASE ? WHEN 'off_track' THEN 0 WHEN 'at_risk' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END",
          outcome.health
        ),
      asc_nulls_last: outcome.target_date,
      desc: outcome.inserted_at
    )
    |> preload([outcome], [:owner, reviews: ^outcome_reviews_query()])
    |> Repo.all()
  end

  def list_active_outcomes(account_or_id), do: list_outcomes(account_or_id, statuses: ["active"])

  def get_outcome(id) when is_binary(id) do
    Outcome
    |> preload([:account, :owner, reviews: ^outcome_reviews_query()])
    |> Repo.get(id)
  end

  def get_outcome(%Account{id: account_id}, id) when is_binary(id) do
    Outcome
    |> where([outcome], outcome.account_id == ^account_id)
    |> preload([:owner, reviews: ^outcome_reviews_query()])
    |> Repo.get(id)
  end

  def change_outcome(account_or_outcome, attrs \\ %{})

  def change_outcome(%Account{} = account, attrs) do
    %Outcome{account_id: account.id}
    |> Outcome.changeset(attrs)
  end

  def change_outcome(%Outcome{} = outcome, attrs) when is_map(attrs) do
    Outcome.changeset(outcome, attrs)
  end

  def create_outcome(%Account{} = account, attrs, author \\ nil) when is_map(attrs) do
    changeset =
      %Outcome{account_id: account.id, owner_id: author && author.id}
      |> Outcome.changeset(attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, outcome} ->
        Search.index_account_outcome(outcome)
        audit_outcome("account_outcome.created", outcome, changeset, actor: author)

      _result ->
        :ok
    end)
  end

  def update_outcome(%Outcome{} = outcome, attrs) when is_map(attrs) do
    attrs = attrs |> stringify_keys() |> stamp_outcome_status(outcome.status)
    changeset = Outcome.changeset(outcome, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        Search.index_account_outcome(updated)
        audit_outcome("account_outcome.updated", updated, changeset)

      _result ->
        :ok
    end)
  end

  def change_outcome_review(%Outcome{} = outcome, attrs \\ %{}) do
    attrs = Map.put_new(attrs, "reviewed_at", utc_now())

    %OutcomeReview{outcome_id: outcome.id}
    |> OutcomeReview.changeset(attrs)
  end

  def create_outcome_review(%Outcome{} = outcome, attrs, author \\ nil) when is_map(attrs) do
    attrs = Map.put_new(attrs, "reviewed_at", utc_now())

    changeset =
      %OutcomeReview{outcome_id: outcome.id, author_id: author && author.id}
      |> OutcomeReview.changeset(attrs)

    Repo.transaction(fn ->
      with {:ok, review} <- Repo.insert(changeset),
           {:ok, updated_outcome} <-
             outcome
             |> Outcome.changeset(%{health: review.health, reviewed_at: review.reviewed_at})
             |> Repo.update() do
        Search.index_account_outcome(updated_outcome)
        audit_outcome_review("account_outcome.reviewed", review, changeset, actor: author)
        review
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_filter_outcome_statuses(query, nil), do: query
  defp maybe_filter_outcome_statuses(query, []), do: query

  defp maybe_filter_outcome_statuses(query, statuses) when is_list(statuses) do
    where(query, [outcome], outcome.status in ^statuses)
  end

  defp outcome_reviews_query do
    from(review in OutcomeReview,
      order_by: [desc: review.reviewed_at, desc: review.inserted_at],
      preload: [:author]
    )
  end

  defp stamp_outcome_status(attrs, current_status) do
    next_status = Map.get(attrs, "status", Map.get(attrs, :status, current_status))
    now = utc_now()

    cond do
      next_status == "achieved" and current_status != "achieved" ->
        attrs |> Map.put_new("achieved_at", now) |> Map.put_new("closed_at", now)

      next_status in ["missed", "abandoned"] and next_status != current_status ->
        Map.put_new(attrs, "closed_at", now)

      next_status == "active" and current_status != "active" ->
        attrs |> Map.put("achieved_at", nil) |> Map.put("closed_at", nil)

      true ->
        attrs
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  def change_term(%Account{} = account), do: change_term(account, %{})
  def change_term(%Term{} = term), do: change_term(term, %{})

  def change_term(%Account{} = account, attrs) when is_map(attrs) do
    %Term{account_id: account.id, source: "atlas"}
    |> Term.changeset(attrs)
  end

  def change_term(%Term{} = term, attrs) when is_map(attrs) do
    Term.changeset(term, attrs)
  end

  @doc """
  Builds a changeset for a brand new term seeded from an existing one, ready to
  be reviewed in the term modal. Pricing, seats, deployment and PO are copied
  over, and the date window is shifted forward so the new term continues right
  where the previous one ended, keeping the same duration.
  """
  def renew_term_changeset(%Account{} = account, %Term{} = term) do
    %Term{account_id: account.id, source: "atlas"}
    |> Term.changeset(renewal_attrs(term))
  end

  defp renewal_attrs(%Term{} = term) do
    {start_date, end_date} = renewal_window(term)

    %{
      payment: term.payment,
      start_date: start_date,
      end_date: end_date,
      price_per_seat: term.price_per_seat,
      seats: term.seats,
      discount: term.discount,
      total: term.total,
      currency: term.currency,
      on_premise: term.on_premise,
      renewal_notice_weeks: term.renewal_notice_weeks,
      po_number: term.po_number
    }
  end

  defp renewal_window(%Term{start_date: start_date, end_date: end_date})
       when not is_nil(start_date) and not is_nil(end_date) do
    next_start_date = Date.add(end_date, 1)

    {next_start_date, Date.add(next_start_date, Date.diff(end_date, start_date))}
  end

  defp renewal_window(%Term{start_date: start_date}), do: {start_date, nil}

  def create_term(%Account{} = account, attrs) when is_map(attrs) do
    changeset =
      %Term{account_id: account.id, source: "atlas"}
      |> Term.changeset(attrs)

    Repo.transaction(fn ->
      with {:ok, term} <- Repo.insert(changeset),
           {:ok, _account} <- sync_account_commercial_summary_from_terms(term.account_id) do
        audit_term("term.created", term, changeset)
        term
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_term(%Term{} = term, attrs) when is_map(attrs) do
    changeset = Term.changeset(term, attrs)

    Repo.transaction(fn ->
      with {:ok, updated} <- Repo.update(changeset),
           {:ok, _account} <- sync_account_commercial_summary_from_terms(updated.account_id) do
        audit_term("term.updated", updated, changeset)
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_term(%Term{} = term) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(term),
           {:ok, _account} <- sync_account_commercial_summary_from_terms(deleted.account_id) do
        audit_term("term.deleted", deleted, %{})
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_term(%Account{} = account, id) do
    Repo.get_by(Term, id: id, account_id: account.id)
  end

  @doc """
  Lists an account's contract terms, most recent first (by start date). The
  first element is the latest term, which agents can copy to seed a renewal.
  """
  def list_terms(%Account{} = account) do
    Term
    |> where([term], term.account_id == ^account.id)
    |> order_by([term], desc: term.start_date)
    |> Repo.all()
  end

  defp sync_account_commercial_summary_from_terms(account_id) when is_binary(account_id) do
    with %Account{} = account <- Repo.get(Account, account_id),
         %Term{} = term <- current_summary_term(account_id) do
      attrs = account_summary_attrs(term)
      changeset = Account.edit_changeset(account, attrs)

      if changeset.changes == %{} do
        {:ok, account}
      else
        changeset
        |> Repo.update()
        |> tap(fn
          {:ok, updated} ->
            audit_account("account.commercial_summary.synced", updated, %{
              "changed" => Audit.changeset_changes(changeset),
              "path" => "/commercial/sales/accounts/#{updated.id}",
              "term_id" => term.id
            })

          _result ->
            :ok
        end)
      end
    else
      nil -> {:ok, nil}
    end
  end

  defp current_summary_term(account_id) do
    Term
    |> where([term], term.account_id == ^account_id)
    |> order_by([term], desc: term.start_date, desc: term.inserted_at)
    |> Repo.all()
    |> ContractValue.current_term()
  end

  defp account_summary_attrs(%Term{} = term) do
    %{
      current_value: term.total,
      next_renewal_date: term.end_date
    }
    |> put_present(:currency, term.currency)
  end

  defp put_present(attrs, _key, nil), do: attrs
  defp put_present(attrs, _key, ""), do: attrs
  defp put_present(attrs, key, value), do: Map.put(attrs, key, value)

  def change_account_handle(%Account{} = account, attrs \\ %{}) do
    %AccountHandle{}
    |> AccountHandle.changeset(account_handle_params(account, attrs))
  end

  def create_account_handle(%Account{} = account, attrs) when is_map(attrs) do
    changeset =
      %AccountHandle{}
      |> AccountHandle.changeset(account_handle_params(account, attrs))

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, account_handle} ->
        audit_account_handle("account_handle.created", account_handle, changeset)
        broadcast_handle_upsert(account, account_handle)

      _result ->
        :ok
    end)
  end

  def delete_account_handle(%Account{} = account, handle_id) do
    case Repo.get_by(AccountHandle, id: handle_id, account_id: account.id) do
      nil ->
        {:error, :not_found}

      account_handle ->
        Repo.delete(account_handle)
        |> tap(fn
          {:ok, deleted} ->
            audit_account_handle("account_handle.deleted", deleted, %{})
            HandleRegistry.broadcast_change(%{action: :delete, handle: deleted.handle})

          _result ->
            :ok
        end)
    end
  end

  defp broadcast_handle_upsert(%Account{} = account, %AccountHandle{} = handle) do
    HandleRegistry.broadcast_change(%{
      action: :upsert,
      handle: handle.handle,
      entry: %{
        account_id: account.id,
        account_key: account.account_key,
        name: account.name,
        primary_domain: account.primary_domain,
        plan_tier: account.plan_tier
      }
    })
  end

  defp audit_account(action, %Account{} = account, metadata_or_changeset, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "account",
        target_id: account.id,
        target_label: account.name,
        metadata: audit_metadata(metadata_or_changeset)
      },
      opts
    )
  end

  defp audit_contact(action, %Contact{} = contact, metadata_or_changeset, opts \\ []) do
    audit_account_child(
      action,
      "contact",
      contact.id,
      first_present([contact.full_name, contact.email]),
      contact.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_event(action, %Event{} = event, metadata_or_changeset, opts) do
    audit_account_child(
      action,
      "account_event",
      event.id,
      event.title,
      event.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_outcome(action, %Outcome{} = outcome, metadata_or_changeset, opts \\ []) do
    audit_account_child(
      action,
      "account_outcome",
      outcome.id,
      outcome.title,
      outcome.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_outcome_review(action, %OutcomeReview{} = review, metadata_or_changeset, opts) do
    outcome = Repo.get!(Outcome, review.outcome_id)

    audit_account_child(
      action,
      "account_outcome_review",
      review.id,
      outcome.title,
      outcome.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_term(action, %Term{} = term, metadata_or_changeset, opts \\ []) do
    audit_account_child(
      action,
      "term",
      term.id,
      term_label(term),
      term.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_account_handle(action, %AccountHandle{} = account_handle, metadata_or_changeset, opts \\ []) do
    audit_account_child(
      action,
      "account_handle",
      account_handle.id,
      account_handle.handle,
      account_handle.account_id,
      metadata_or_changeset,
      opts
    )
  end

  defp audit_account_child(action, target_type, target_id, target_label, account_id, metadata_or_changeset, opts) do
    metadata =
      metadata_or_changeset
      |> audit_metadata()
      |> put_metadata("account_id", account_id)
      |> put_account_path(account_id)

    Audit.record(
      action,
      %{
        target_type: target_type,
        target_id: target_id,
        target_label: target_label,
        metadata: metadata
      },
      opts
    )
  end

  defp audit_metadata(%Ecto.Changeset{} = changeset), do: %{"changed" => Audit.changeset_changes(changeset)}
  defp audit_metadata(nil), do: %{}
  defp audit_metadata(metadata) when is_map(metadata), do: metadata
  defp audit_metadata(value), do: %{"value" => value}

  defp put_metadata(metadata, _key, nil), do: metadata
  defp put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp put_account_path(metadata, account_id) when is_binary(account_id) and account_id != "" do
    Map.put_new(metadata, "path", "/commercial/sales/accounts/#{account_id}")
  end

  defp put_account_path(metadata, _account_id), do: metadata

  defp term_label(%Term{} = term) do
    first_present([
      term.po_number,
      Enum.join(Enum.reject([date_label(term.start_date), date_label(term.end_date)], &is_nil/1), " - "),
      term.payment
    ])
  end

  defp date_label(%Date{} = date), do: Date.to_iso8601(date)
  defp date_label(_date), do: nil

  defp first_present(values) do
    Enum.find_value(values, fn value ->
      case present_text(value) do
        nil -> nil
        "" -> nil
        text -> text
      end
    end)
  end

  defp present_text(value) when is_binary(value), do: String.trim(value)
  defp present_text(nil), do: nil
  defp present_text(value), do: to_string(value)

  defp note_params(account, attrs, author) do
    body =
      attrs
      |> Map.get("body", Map.get(attrs, :body))
      |> case do
        nil ->
          nil

        value ->
          value
          |> to_string()
          |> String.trim()
          |> case do
            "" -> nil
            trimmed -> trimmed
          end
      end

    %{
      "account_id" => account.id,
      "author_id" => author && author.id,
      "external_id" => "atlas-note:#{Ecto.UUID.generate()}",
      "source" => "atlas",
      "kind" => "note",
      "title" => "Note",
      "body" => body,
      "occurred_at" => DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp account_handle_params(account, attrs) do
    attrs
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("account_id", account.id)
    |> Map.put_new("source", "atlas")
  end

  defp refresh_contact_count(account_id) do
    contacts_count =
      Contact
      |> where([contact], contact.account_id == ^account_id)
      |> select([contact], count(contact.id))
      |> Repo.one()

    Account
    |> where([account], account.id == ^account_id)
    |> Repo.update_all(set: [contacts_count: contacts_count])
  end
end
