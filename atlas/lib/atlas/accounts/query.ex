defmodule Atlas.Accounts.Query do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.ContractValue
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Lifecycle
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Accounts.Term
  alias Atlas.Documents.Document
  alias Atlas.Repo

  @inactive_statuses ["churned"]
  @sortable_fields ~w(name lifecycle deal_stage value next_milestone contacts)

  def sortable_fields, do: @sortable_fields

  def list_accounts(opts \\ []) do
    filters = Keyword.get(opts, :filters, [])
    query = Keyword.get(opts, :query)
    sort_by = Keyword.get(opts, :sort_by)
    sort_order = Keyword.get(opts, :sort_order, "desc")
    pinned_segment = Keyword.get(opts, :pinned_segment)

    Account
    |> real_account_filter(:root)
    |> maybe_pin_segment(pinned_segment)
    |> maybe_apply_filters(filters)
    |> apply_sort(sort_by, sort_order)
    |> maybe_filter_query(query)
    |> preload_commercial_terms()
    |> Repo.all()
    |> sort_by_contract_value(sort_by, sort_order)
  end

  def list_license_eligible_accounts do
    Account
    |> real_account_filter(:root)
    |> where(
      [account],
      account.segment == :customer or account.deal_stage in ^Account.license_deal_stages()
    )
    |> apply_sort(nil, nil)
    |> preload_commercial_terms()
    |> Repo.all()
  end

  defp maybe_pin_segment(query, nil), do: query

  defp maybe_pin_segment(query, segment) when is_atom(segment) do
    where(query, [account], account.segment == ^segment)
  end

  defp apply_sort(query, sort_by, sort_order) when sort_by in @sortable_fields do
    direction = sort_direction(sort_order)
    sort_by_field(query, sort_by, direction, nulls_direction(direction))
  end

  defp apply_sort(query, _sort_by, _sort_order) do
    order_by(query, [account],
      desc_nulls_last: account.latest_activity_at,
      asc: account.name
    )
  end

  defp sort_direction("asc"), do: :asc
  defp sort_direction(_), do: :desc

  defp nulls_direction(:asc), do: :asc_nulls_last
  defp nulls_direction(:desc), do: :desc_nulls_last

  defp sort_by_field(query, "name", direction, _nulls) do
    order_by(query, [account], [{^direction, account.name}])
  end

  defp sort_by_field(query, "lifecycle", direction, _nulls) do
    order_by(query, [account], [{^direction, account.segment}, asc: account.name])
  end

  defp sort_by_field(query, "deal_stage", _direction, nulls) do
    order_by(query, [account], [{^nulls, account.deal_stage}, asc: account.name])
  end

  # The value column shows the term-derived contract value, which no column
  # holds. The database only settles ties here; sort_by_contract_value/3 orders
  # the loaded rows.
  defp sort_by_field(query, "value", _direction, _nulls) do
    order_by(query, [account], asc: account.name)
  end

  defp sort_by_field(query, "next_milestone", _direction, nulls) do
    order_by(query, [account], [
      {^nulls, account.next_renewal_date},
      {^nulls, account.latest_activity_at},
      asc: account.name
    ])
  end

  defp sort_by_field(query, "contacts", direction, _nulls) do
    order_by(query, [account], [{^direction, account.contacts_count}, asc: account.name])
  end

  defp sort_by_contract_value(accounts, "value", sort_order) do
    today = Date.utc_today()
    direction = sort_direction(sort_order)

    Enum.sort_by(accounts, &contract_value(&1, today), &compare_contract_values(&1, &2, direction))
  end

  defp sort_by_contract_value(accounts, _sort_by, _sort_order), do: accounts

  defp contract_value(account, today) do
    {value, _currency} = ContractValue.value(account, today)
    value
  end

  defp compare_contract_values(nil, nil, _direction), do: true
  defp compare_contract_values(nil, _right, _direction), do: false
  defp compare_contract_values(_left, nil, _direction), do: true
  defp compare_contract_values(left, right, :asc), do: Decimal.compare(left, right) != :gt
  defp compare_contract_values(left, right, :desc), do: Decimal.compare(left, right) != :lt

  def list_account_ids do
    Account
    |> real_account_filter(:root)
    |> select([account], account.id)
    |> Repo.all()
  end

  def list_overview_summary_candidate_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit)

    Account
    |> real_account_filter(:root)
    |> where(
      [account],
      is_nil(account.overview_summary_generated_at) or
        account.updated_at > account.overview_summary_generated_at or
        (not is_nil(account.latest_activity_at) and account.latest_activity_at > account.overview_summary_generated_at)
    )
    |> order_by([account], desc_nulls_last: account.latest_activity_at, desc: account.updated_at, asc: account.name)
    |> maybe_limit(limit)
    |> select([account], account.id)
    |> Repo.all()
  end

  def list_outcome_review_candidate_ids(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    stale_before = Keyword.get(opts, :stale_before, DateTime.add(now, -14, :day))
    limit = Keyword.get(opts, :limit, 50)

    Outcome
    |> where([outcome], outcome.status == "active")
    |> where([outcome], is_nil(outcome.reviewed_at) or outcome.reviewed_at < ^stale_before)
    |> order_by([outcome], asc_nulls_first: outcome.reviewed_at, asc_nulls_last: outcome.target_date)
    |> maybe_limit(limit)
    |> select([outcome], outcome.id)
    |> Repo.all()
  end

  def list_outcome_proposal_candidate_ids(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    stale_before = Keyword.get(opts, :stale_before, DateTime.add(now, -14, :day))
    limit = Keyword.get(opts, :limit, 25)

    stale_outcome =
      from(outcome in Outcome,
        where:
          outcome.account_id == parent_as(:account).id and outcome.status == "active" and
            (is_nil(outcome.reviewed_at) or outcome.reviewed_at < ^stale_before),
        select: 1
      )

    Account
    |> from(as: :account)
    |> real_account_filter(:root)
    |> where([account], is_nil(account.status) or account.status != "churned")
    |> where(
      [account],
      is_nil(account.outcome_proposals_checked_at) or
        account.updated_at > account.outcome_proposals_checked_at or
        (not is_nil(account.latest_activity_at) and
           account.latest_activity_at > account.outcome_proposals_checked_at) or
        exists(stale_outcome)
    )
    |> order_by([account],
      asc_nulls_first: account.outcome_proposals_checked_at,
      desc_nulls_last: account.latest_activity_at,
      asc: account.name
    )
    |> maybe_limit(limit)
    |> select([account], account.id)
    |> Repo.all()
  end

  def list_parent_account_options(account_id \\ nil) do
    Account
    |> real_account_filter(:root)
    |> maybe_exclude_account(account_id)
    |> order_by([account], asc: account.name)
    |> select([account], %{
      id: account.id,
      name: account.name,
      primary_domain: account.primary_domain
    })
    |> Repo.all()
  end

  defp maybe_exclude_account(query, nil), do: query

  defp maybe_exclude_account(query, account_id) when is_binary(account_id) do
    where(query, [account], account.id != ^account_id)
  end

  @doc """
  Lists active outcomes that need attention, with off-track outcomes first and
  at-risk outcomes second.

  Returns `{items, meta}` where `meta` carries cursor-style pagination info
  compatible with `AtlasWeb.PaginationComponents.pagination/1`. Cursors are
  opaque integer offsets; pass `:offset` to load a later page and `:limit` to
  size the page. Offset pagination is delegated to Flop.
  """
  def list_attention_outcomes(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)
    offset = opts |> Keyword.get(:offset, 0) |> normalize_offset()

    query =
      Outcome
      |> where([outcome], outcome.status == "active" and outcome.health in ["off_track", "at_risk"])
      |> join(:inner, [outcome], account in Account, on: account.id == outcome.account_id, as: :account)
      |> real_account_filter(:joined)
      |> order_by([outcome, account: account],
        asc:
          fragment(
            "CASE ? WHEN 'off_track' THEN 0 WHEN 'at_risk' THEN 1 ELSE 2 END",
            outcome.health
          ),
        asc_nulls_last: outcome.target_date,
        asc: account.name
      )
      |> preload([_outcome, account: account], account: account, reviews: ^outcome_reviews_query())

    {items, flop_meta} = Flop.run(query, %Flop{limit: limit, offset: offset}, for: Outcome)

    meta = %{
      has_next_page?: flop_meta.has_next_page?,
      has_previous_page?: flop_meta.has_previous_page?,
      start_cursor: Integer.to_string(flop_meta.previous_offset || 0),
      end_cursor: Integer.to_string(flop_meta.next_offset || offset + limit)
    }

    {items, meta}
  end

  @doc """
  Lists active customer accounts for the weekly outcome review.
  """
  def list_outcome_review_accounts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    company_slack_posted_since = Keyword.get(opts, :company_slack_posted_since)

    Account
    |> active_customer_account_filter(:root)
    |> maybe_exclude_recent_company_slack_posts(:root, company_slack_posted_since)
    |> order_by([account],
      desc_nulls_last: account.latest_activity_at,
      asc_nulls_last: account.next_renewal_date,
      asc: account.name
    )
    |> limit(^limit)
    |> preload(outcomes: ^active_outcomes_query())
    |> Repo.all()
  end

  @doc """
  Lists recent timeline updates across active customer accounts.
  """
  def list_outcome_review_updates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    company_slack_posted_since = Keyword.get(opts, :company_slack_posted_since)

    Event
    |> join(:inner, [event], account in Account, on: account.id == event.account_id, as: :account)
    |> active_customer_account_filter(:joined)
    |> maybe_exclude_recent_company_slack_posts(:joined, company_slack_posted_since)
    |> order_by([event], desc: event.occurred_at, desc: event.inserted_at)
    |> preload([_event, account: account], account: account)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists active customers with upcoming renewal dates, nearest first.
  """
  def list_upcoming_renewals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)
    today = Keyword.get(opts, :today, Date.utc_today())
    until = Keyword.get(opts, :until)

    Account
    |> active_customer_account_filter(:root)
    |> where([account], not is_nil(account.next_renewal_date))
    |> where([account], account.next_renewal_date >= ^today)
    |> maybe_filter_renewal_until(until)
    |> order_by([account], asc: account.next_renewal_date, desc_nulls_last: account.current_value, asc: account.name)
    |> limit(^limit)
    |> preload_commercial_terms()
    |> Repo.all()
  end

  defp maybe_filter_renewal_until(query, nil), do: query

  defp maybe_filter_renewal_until(query, %Date{} = until) do
    where(query, [account], account.next_renewal_date <= ^until)
  end

  defp normalize_offset(offset) when is_integer(offset) and offset > 0, do: offset
  defp normalize_offset(_offset), do: 0

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp maybe_exclude_recent_company_slack_posts(query, _binding, nil), do: query

  defp maybe_exclude_recent_company_slack_posts(query, :root, %DateTime{} = company_slack_posted_since) do
    where(
      query,
      [account],
      is_nil(account.outcome_review_company_slack_posted_at) or
        account.outcome_review_company_slack_posted_at < ^company_slack_posted_since
    )
  end

  defp maybe_exclude_recent_company_slack_posts(query, :joined, %DateTime{} = company_slack_posted_since) do
    where(
      query,
      [account: account],
      is_nil(account.outcome_review_company_slack_posted_at) or
        account.outcome_review_company_slack_posted_at < ^company_slack_posted_since
    )
  end

  @doc """
  Returns counts used by the sales overview KPI tiles.
  """
  def sales_overview_counts(today \\ Date.utc_today()) do
    health_counts =
      Outcome
      |> where([outcome], outcome.status == "active")
      |> join(:inner, [outcome], account in Account, on: account.id == outcome.account_id, as: :account)
      |> real_account_filter(:joined)
      |> group_by([outcome], outcome.health)
      |> select([outcome], {outcome.health, count(outcome.id)})
      |> Repo.all()
      |> Map.new()

    overdue_outcomes =
      Outcome
      |> where([outcome], outcome.status == "active" and outcome.target_date < ^today)
      |> Repo.aggregate(:count, :id)

    accounts_without_outcomes =
      from(account in Account, as: :account)
      |> real_account_filter(:root)
      |> where([account], is_nil(account.status) or account.status not in ^@inactive_statuses)
      |> where(
        [account: account],
        not exists(
          from(outcome in Outcome,
            where: outcome.account_id == parent_as(:account).id and outcome.status == "active",
            select: 1
          )
        )
      )
      |> Repo.aggregate(:count, :id)

    %{
      on_track: Map.get(health_counts, "on_track", 0),
      at_risk: Map.get(health_counts, "at_risk", 0),
      off_track: Map.get(health_counts, "off_track", 0),
      unknown: Map.get(health_counts, "unknown", 0),
      overdue_outcomes: overdue_outcomes,
      accounts_without_outcomes: accounts_without_outcomes
    }
  end

  def list_stripe_customer_account_ids do
    Account
    |> real_account_filter(:root)
    |> where([account], not is_nil(account.stripe_customer_id) and account.stripe_customer_id != "")
    |> order_by([account], asc: account.name)
    |> select([account], account.id)
    |> Repo.all()
  end

  def account_filters do
    lifecycles =
      distinct_segments()
      |> Enum.map(&Lifecycle.from_segment/1)
      |> Enum.uniq_by(& &1.key)
      |> Enum.sort_by(fn lifecycle -> {Lifecycle.sort_order(lifecycle.key), lifecycle.label} end)
      |> Enum.map(&Map.take(&1, [:key, :label]))

    %{
      lifecycles: lifecycles
    }
  end

  def account_counts do
    counts =
      Account
      |> real_account_filter(:root)
      |> group_by([account], account.segment)
      |> select([account], {account.segment, count(account.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: Enum.sum(Map.values(counts)),
      customer: Map.get(counts, :customer, 0),
      lead: Map.get(counts, :lead, 0),
      prospect: Map.get(counts, :prospect, 0)
    }
  end

  defp preload_commercial_terms(query) do
    preload(query, terms: ^commercial_terms_query())
  end

  defp commercial_terms_query do
    from(term in Term, order_by: [desc: term.start_date, desc: term.inserted_at])
  end

  defp real_account_filter(query, :root) do
    where(query, [account], is_nil(account.not_an_account_at))
  end

  defp real_account_filter(query, :joined) do
    where(query, [account: account], is_nil(account.not_an_account_at))
  end

  defp active_customer_account_filter(query, :root) do
    query
    |> real_account_filter(:root)
    |> where(
      [account],
      account.segment == :customer and (is_nil(account.status) or account.status not in ^@inactive_statuses)
    )
  end

  defp active_customer_account_filter(query, :joined) do
    query
    |> real_account_filter(:joined)
    |> where(
      [account: account],
      account.segment == :customer and (is_nil(account.status) or account.status not in ^@inactive_statuses)
    )
  end

  def get_account(id) do
    case Repo.get(Account, id) do
      nil ->
        nil

      account ->
        Repo.preload(account,
          parent_account: [],
          child_accounts:
            from(child_account in Account,
              where: is_nil(child_account.not_an_account_at),
              order_by: [asc: child_account.name]
            ),
          account_handles:
            from(account_handle in AccountHandle,
              order_by: [asc: account_handle.handle]
            ),
          contacts: from(contact in Contact, order_by: [asc: contact.full_name, asc: contact.email]),
          invoices: from(invoice in Invoice, order_by: [asc: invoice.due_date]),
          terms: commercial_terms_query(),
          service_levels:
            from(service_level in ServiceLevel,
              order_by: [
                asc: service_level.category,
                asc_nulls_last: service_level.applies_until,
                asc: service_level.name
              ],
              preload: [:document, :extraction_check]
            ),
          service_level_extraction_checks:
            from(check in ServiceLevelExtractionCheck,
              order_by: [desc: check.started_at, desc: check.inserted_at],
              preload: [:document]
            ),
          documents:
            from(document in Document,
              where: document.source != "letter",
              order_by: [desc: document.document_date, desc: document.inserted_at],
              preload: [:document_type, :correspondent, :tags]
            ),
          events: {from(event in Event, order_by: [desc: event.occurred_at, desc: event.inserted_at]), [:author]},
          outcomes:
            {from(outcome in Outcome,
               order_by: [
                 fragment(
                   "CASE ? WHEN 'active' THEN 0 WHEN 'achieved' THEN 1 WHEN 'missed' THEN 2 ELSE 3 END",
                   outcome.status
                 ),
                 fragment(
                   "CASE ? WHEN 'off_track' THEN 0 WHEN 'at_risk' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END",
                   outcome.health
                 ),
                 asc_nulls_last: outcome.target_date,
                 desc: outcome.inserted_at
               ]
             ), [:owner, reviews: outcome_reviews_query()]},
          outcome_proposals:
            {from(proposal in OutcomeProposal,
               order_by: [desc: proposal.inserted_at],
               limit: 20
             ), [:outcome, :source_event, :reviewed_by]}
        )
    end
  end

  defp maybe_apply_filters(query, filters) when is_list(filters) do
    Enum.reduce(filters, query, &apply_filter/2)
  end

  defp maybe_filter_query(queryable, nil), do: queryable
  defp maybe_filter_query(queryable, ""), do: queryable

  defp maybe_filter_query(queryable, query) do
    case String.trim(query) do
      "" ->
        queryable

      trimmed_query ->
        search_term = "%#{trimmed_query}%"

        handle_match =
          from(account_handle in AccountHandle,
            where:
              parent_as(:account).id == account_handle.account_id and
                ilike(coalesce(account_handle.handle, ""), ^search_term),
            select: 1
          )

        queryable
        |> from(as: :account)
        |> where(
          [account: account],
          ilike(account.name, ^search_term) or
            ilike(coalesce(account.description, ""), ^search_term) or
            ilike(coalesce(account.primary_domain, ""), ^search_term) or
            exists(handle_match)
        )
    end
  end

  defp apply_filter(%{id: "lifecycle", value: nil}, query), do: query

  defp apply_filter(%{id: "lifecycle", operator: operator, value: value}, query) do
    matching_segments =
      distinct_segments()
      |> Enum.filter(&(Lifecycle.key(&1) == value))

    apply_lifecycle_filter(query, operator, matching_segments)
  end

  defp apply_filter(%{id: "deal_stage", value: nil}, query), do: query

  defp apply_filter(%{id: "deal_stage", operator: :==, value: value}, query),
    do: where(query, [account], account.deal_stage == ^value)

  defp apply_filter(%{id: "deal_stage", operator: :!=, value: value}, query),
    do: where(query, [account], is_nil(account.deal_stage) or account.deal_stage != ^value)

  defp apply_filter(%{id: "needs_attention", value: nil}, query), do: query

  defp apply_filter(%{id: "needs_attention", operator: :==, value: _value}, query) do
    attention_keys = DealStage.attention_keys()
    where(query, [account], account.deal_stage in ^attention_keys)
  end

  defp apply_filter(%{id: "needs_attention", operator: :!=, value: _value}, query) do
    attention_keys = DealStage.attention_keys()
    where(query, [account], is_nil(account.deal_stage) or account.deal_stage not in ^attention_keys)
  end

  defp apply_filter(_filter, query), do: query

  defp apply_operator_filter(query, :==, condition) do
    where(query, ^condition)
  end

  defp apply_operator_filter(query, :!=, condition) do
    negated_condition = dynamic(not (^condition))
    where(query, ^negated_condition)
  end

  defp apply_operator_filter(query, _operator, _condition), do: query

  defp apply_lifecycle_filter(query, :==, []), do: where(query, false)
  defp apply_lifecycle_filter(query, :!=, []), do: query

  defp apply_lifecycle_filter(query, operator, matching_segments) do
    condition =
      Enum.reduce(matching_segments, dynamic(false), fn segment, dynamic_query ->
        dynamic([account], ^dynamic_query or account.segment == ^segment)
      end)

    apply_operator_filter(query, operator, condition)
  end

  defp distinct_segments do
    Account
    |> real_account_filter(:root)
    |> select([account], account.segment)
    |> distinct(true)
    |> Repo.all()
  end

  defp outcome_reviews_query do
    from(review in OutcomeReview,
      order_by: [desc: review.reviewed_at, desc: review.inserted_at],
      preload: [:author]
    )
  end

  defp active_outcomes_query do
    from(outcome in Outcome,
      where: outcome.status == "active",
      order_by: [
        fragment(
          "CASE ? WHEN 'off_track' THEN 0 WHEN 'at_risk' THEN 1 WHEN 'unknown' THEN 2 ELSE 3 END",
          outcome.health
        ),
        asc_nulls_last: outcome.target_date
      ],
      preload: [reviews: ^outcome_reviews_query()]
    )
  end
end
