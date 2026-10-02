defmodule Atlas.Finance.Query do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Finance.Account
  alias Atlas.Finance.Category
  alias Atlas.Finance.Source
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  @default_limit 100
  @default_page_size 25

  def list_sources(_opts \\ []) do
    Source
    |> preload(:atlas_account)
    |> order_by([source], desc_nulls_last: source.last_successful_sync_at, asc: source.name)
    |> Repo.all()
  end

  def list_accounts(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    provider = Keyword.get(opts, :provider)
    source_key = Keyword.get(opts, :source_key)
    atlas_account_id = Keyword.get(opts, :atlas_account_id)
    atlas_account_key = Keyword.get(opts, :atlas_account_key)
    currency = Keyword.get(opts, :currency)
    query = Keyword.get(opts, :query)

    Account
    |> join(:inner, [account], source in assoc(account, :source), as: :source)
    |> join(:left, [source: source], atlas_account in assoc(source, :atlas_account), as: :atlas_account)
    |> preload([source: source, atlas_account: atlas_account], source: {source, atlas_account: atlas_account})
    |> maybe_filter_account_provider(provider)
    |> maybe_filter_source_key(source_key)
    |> maybe_filter_atlas_account_id(atlas_account_id)
    |> maybe_filter_atlas_account_key(atlas_account_key)
    |> maybe_filter_currency(currency)
    |> maybe_filter_account_query(query)
    |> order_by([account], asc: account.provider, desc: account.main, asc: account.currency, asc: account.name)
    |> maybe_limit(limit)
    |> Repo.all()
  end

  def list_categories(opts \\ []) do
    direction = Keyword.get(opts, :direction)

    Category
    |> maybe_filter_category_direction(direction)
    |> order_by([category], asc: category.name)
    |> Repo.all()
  end

  def list_transactions(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    opts
    |> transactions_query()
    |> limit(^limit)
    |> Repo.all()
  end

  @doc false
  def list_transactions_for_reconciliation(opts) do
    opts
    |> transactions_query()
    |> Repo.all()
  end

  def list_transactions_page(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> normalize_page_size()
    page = opts |> Keyword.get(:page, 1) |> normalize_page()
    offset = (page - 1) * page_size

    query = transactions_query(opts)
    {transactions, flop_meta} = Flop.run(query, %Flop{limit: page_size, offset: offset}, for: Transaction)
    total_count = flop_meta.total_count || length(transactions)

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages(total_count, page_size),
      has_next_page?: flop_meta.has_next_page?,
      has_previous_page?: flop_meta.has_previous_page?
    }

    {transactions, meta}
  end

  defp transactions_query(opts) do
    Transaction
    |> join(:inner, [transaction], account in assoc(transaction, :account), as: :account)
    |> join(:inner, [account: account], source in assoc(account, :source), as: :source)
    |> join(:left, [source: source], atlas_account in assoc(source, :atlas_account), as: :atlas_account)
    |> join(:left, [transaction], category in assoc(transaction, :category), as: :category)
    |> preload(
      [account: account, source: source, atlas_account: atlas_account, category: category],
      account: {account, source: {source, atlas_account: atlas_account}},
      category: category
    )
    |> maybe_filter_transaction_id(Keyword.get(opts, :id))
    |> maybe_filter_provider(Keyword.get(opts, :provider))
    |> maybe_filter_source_key(Keyword.get(opts, :source_key))
    |> maybe_filter_atlas_account_id(Keyword.get(opts, :atlas_account_id))
    |> maybe_filter_atlas_account_key(Keyword.get(opts, :atlas_account_key))
    |> maybe_filter_account(Keyword.get(opts, :account_id))
    |> maybe_filter_transaction_currency(Keyword.get(opts, :currency))
    |> maybe_filter_direction(Keyword.get(opts, :direction))
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_kind(Keyword.get(opts, :kind))
    |> maybe_filter_category_id(Keyword.get(opts, :category_id))
    |> maybe_filter_category_slug(Keyword.get(opts, :category_slug))
    |> maybe_filter_uncategorized(Keyword.get(opts, :uncategorized))
    |> maybe_filter_date_from(Keyword.get(opts, :date_from))
    |> maybe_filter_date_to(Keyword.get(opts, :date_to))
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> order_by([transaction],
      desc_nulls_last: transaction.settled_at,
      desc_nulls_last: transaction.booked_at,
      desc_nulls_last: transaction.provider_updated_at,
      desc: transaction.inserted_at
    )
  end

  defp maybe_filter_category_direction(query, direction) when direction in ["credit", "debit"] do
    where(query, [category], is_nil(category.direction) or category.direction == ^direction)
  end

  defp maybe_filter_category_direction(query, _direction), do: query

  defp maybe_filter_transaction_id(query, id) when is_binary(id) and id != "" do
    where(query, [transaction], transaction.id == ^id)
  end

  defp maybe_filter_transaction_id(query, _id), do: query

  defp maybe_filter_provider(query, provider) when is_binary(provider) and provider != "" do
    where(query, [transaction], transaction.provider == ^provider)
  end

  defp maybe_filter_provider(query, _provider), do: query

  defp maybe_filter_account_provider(query, provider) when is_binary(provider) and provider != "" do
    where(query, [account], account.provider == ^provider)
  end

  defp maybe_filter_account_provider(query, _provider), do: query

  defp maybe_filter_source_key(query, source_key) when is_binary(source_key) and source_key != "" do
    where(query, [source: source], source.config_key == ^source_key)
  end

  defp maybe_filter_source_key(query, _source_key), do: query

  defp maybe_filter_atlas_account_id(query, atlas_account_id)
       when is_binary(atlas_account_id) and atlas_account_id != "" do
    where(query, [source: source], source.atlas_account_id == ^atlas_account_id)
  end

  defp maybe_filter_atlas_account_id(query, _atlas_account_id), do: query

  defp maybe_filter_atlas_account_key(query, atlas_account_key)
       when is_binary(atlas_account_key) and atlas_account_key != "" do
    where(query, [atlas_account: atlas_account], atlas_account.account_key == ^atlas_account_key)
  end

  defp maybe_filter_atlas_account_key(query, _atlas_account_key), do: query

  defp maybe_filter_account(query, account_id) when is_binary(account_id) and account_id != "" do
    where(query, [transaction], transaction.finance_account_id == ^account_id)
  end

  defp maybe_filter_account(query, _account_id), do: query

  defp maybe_filter_transaction_currency(query, currency) when is_binary(currency) and currency != "" do
    where(query, [transaction], transaction.amount_currency == ^currency)
  end

  defp maybe_filter_transaction_currency(query, _currency), do: query

  defp maybe_filter_direction(query, direction) when direction in ["credit", "debit"] do
    where(query, [transaction], transaction.direction == ^direction)
  end

  defp maybe_filter_direction(query, _direction), do: query

  defp maybe_filter_status(query, status) when is_binary(status) and status != "" do
    where(query, [transaction], transaction.status == ^status)
  end

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_kind(query, kind) when is_binary(kind) and kind != "" do
    where(query, [transaction], transaction.kind == ^kind)
  end

  defp maybe_filter_kind(query, _kind), do: query

  defp maybe_filter_category_id(query, category_id) when is_binary(category_id) and category_id != "" do
    where(query, [transaction], transaction.finance_category_id == ^category_id)
  end

  defp maybe_filter_category_id(query, _category_id), do: query

  defp maybe_filter_category_slug(query, category_slug) when is_binary(category_slug) and category_slug != "" do
    where(query, [category: category], category.slug == ^category_slug)
  end

  defp maybe_filter_category_slug(query, _category_slug), do: query

  defp maybe_filter_uncategorized(query, true) do
    where(query, [transaction], is_nil(transaction.finance_category_id))
  end

  defp maybe_filter_uncategorized(query, _uncategorized), do: query

  defp maybe_filter_date_from(query, %DateTime{} = date_from) do
    where(
      query,
      [transaction],
      fragment("coalesce(?, ?, ?)", transaction.settled_at, transaction.booked_at, transaction.provider_updated_at) >=
        ^date_from
    )
  end

  defp maybe_filter_date_from(query, _date_from), do: query

  defp maybe_filter_date_to(query, %DateTime{} = date_to) do
    where(
      query,
      [transaction],
      fragment("coalesce(?, ?, ?)", transaction.settled_at, transaction.booked_at, transaction.provider_updated_at) <=
        ^date_to
    )
  end

  defp maybe_filter_date_to(query, _date_to), do: query

  defp maybe_filter_currency(query, currency) when is_binary(currency) and currency != "" do
    where(query, [account], account.currency == ^currency)
  end

  defp maybe_filter_currency(query, _currency), do: query

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    pattern = "%#{String.trim(value)}%"

    where(
      query,
      [transaction, account: account, source: source, atlas_account: atlas_account],
      ilike(fragment("coalesce(?, '')", transaction.counterparty_name), ^pattern) or
        ilike(fragment("coalesce(?, '')", transaction.description), ^pattern) or
        ilike(fragment("coalesce(?, '')", transaction.reference), ^pattern) or
        ilike(account.name, ^pattern) or
        ilike(source.name, ^pattern) or
        ilike(fragment("coalesce(?, '')", atlas_account.name), ^pattern)
    )
  end

  defp maybe_filter_account_query(query, nil), do: query
  defp maybe_filter_account_query(query, ""), do: query

  defp maybe_filter_account_query(query, value) when is_binary(value) do
    pattern = "%#{String.trim(value)}%"

    where(
      query,
      [account, source: source, atlas_account: atlas_account],
      ilike(account.name, ^pattern) or
        ilike(fragment("coalesce(?, '')", account.iban), ^pattern) or
        ilike(fragment("coalesce(?, '')", account.bic), ^pattern) or
        ilike(source.name, ^pattern) or
        ilike(fragment("coalesce(?, '')", atlas_account.name), ^pattern)
    )
  end

  defp maybe_limit(query, limit_value) when is_integer(limit_value) and limit_value > 0 do
    limit(query, ^limit_value)
  end

  defp maybe_limit(query, _limit_value), do: query

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp normalize_page_size(page_size) when is_integer(page_size) and page_size > 0 do
    min(page_size, @default_limit)
  end

  defp normalize_page_size(page_size) when is_binary(page_size) do
    case Integer.parse(page_size) do
      {page_size, ""} when page_size > 0 -> normalize_page_size(page_size)
      _other -> @default_page_size
    end
  end

  defp normalize_page_size(_page_size), do: @default_page_size

  defp total_pages(0, _page_size), do: 1
  defp total_pages(total_count, page_size), do: div(total_count + page_size - 1, page_size)
end
