defmodule AtlasWeb.FinanceLive.Filters do
  @moduledoc false

  use Gettext, backend: AtlasWeb.Gettext

  alias AtlasWeb.FinanceLive.Formatters
  alias AtlasWeb.FinanceLive.QueryParams
  alias Noora.Filter.Filter, as: FilterDefinition

  def filter_accounts(accounts, filters) do
    source_key = QueryParams.filter_value(filters, "source_key")
    atlas_account_id = QueryParams.filter_value(filters, "atlas_account_id")
    provider = QueryParams.filter_value(filters, "provider")
    currency = QueryParams.filter_value(filters, "currency")
    account_id = QueryParams.filter_value(filters, "account_id")

    Enum.filter(accounts, fn account ->
      matches_source?(account, source_key) and
        matches_atlas_account?(account, atlas_account_id) and
        matches_provider?(account, provider) and
        matches_currency?(account, currency) and
        matches_account?(account, account_id)
    end)
  end

  def define_filters(sources, accounts, categories, transactions) do
    atlas_account_options = atlas_account_options(sources)
    source_options = source_options(sources)
    account_options = account_options(accounts)

    [
      option_filter("provider", gettext("Provider"), provider_options(sources, accounts), &Formatters.humanize_value/1),
      option_filter(
        "atlas_account_id",
        gettext("Company"),
        Enum.map(atlas_account_options, & &1.id),
        Map.new(atlas_account_options, &{&1.id, &1.name}),
        searchable: true
      ),
      option_filter(
        "source_key",
        gettext("Source"),
        Enum.map(source_options, & &1.key),
        Map.new(source_options, &{&1.key, &1.label}),
        searchable: true
      ),
      option_filter(
        "account_id",
        gettext("Account"),
        Enum.map(account_options, & &1.id),
        Map.new(account_options, &{&1.id, Formatters.account_option_label(&1)}),
        searchable: true
      ),
      option_filter("currency", gettext("Currency"), currency_options(accounts, transactions), & &1),
      option_filter("direction", gettext("Direction"), ~w(credit debit), &Formatters.humanize_value/1),
      option_filter(
        "status",
        gettext("Status"),
        transaction_options(transactions, :status),
        &Formatters.humanize_value/1
      ),
      option_filter("kind", gettext("Kind"), transaction_options(transactions, :kind), &Formatters.humanize_value/1),
      option_filter(
        "category_id",
        gettext("Category"),
        Enum.map(categories, & &1.id),
        Map.new(categories, &{&1.id, &1.name}),
        searchable: true
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, options_or_formatter, opts \\ [])

  defp option_filter(id, display_name, options, formatter, opts) when is_function(formatter, 1) do
    option_filter(id, display_name, options, Map.new(options, &{&1, formatter.(&1)}), opts)
  end

  defp option_filter(id, display_name, options, options_display_names, opts) when is_map(options_display_names) do
    %FilterDefinition{
      id: id,
      display_name: display_name,
      type: :option,
      options: options,
      options_display_names: options_display_names,
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false)
    }
  end

  defp matches_source?(_account, nil), do: true
  defp matches_source?(account, source_key), do: account.source.config_key == source_key

  defp matches_atlas_account?(_account, nil), do: true
  defp matches_atlas_account?(account, atlas_account_id), do: account.source.atlas_account_id == atlas_account_id

  defp matches_provider?(_account, nil), do: true
  defp matches_provider?(account, provider), do: account.provider == provider

  defp matches_currency?(_account, nil), do: true

  defp matches_currency?(account, currency),
    do: currency in [account.currency, account.balance_currency, account.available_balance_currency]

  defp matches_account?(_account, nil), do: true
  defp matches_account?(account, account_id), do: account.id == account_id

  defp provider_options(sources, accounts) do
    sources
    |> Enum.map(& &1.provider)
    |> Kernel.++(Enum.map(accounts, & &1.provider))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_options(sources) do
    sources
    |> Enum.map(fn source ->
      %{key: source.config_key, label: Formatters.source_option_label(source)}
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp atlas_account_options(sources) do
    sources
    |> Enum.map(& &1.atlas_account)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  defp account_options(accounts), do: Enum.sort_by(accounts, &Formatters.account_option_label/1)

  defp currency_options(accounts, transactions) do
    accounts
    |> Enum.flat_map(fn account ->
      [account.currency, account.balance_currency, account.available_balance_currency]
    end)
    |> Kernel.++(Enum.map(transactions, & &1.amount_currency))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp transaction_options(transactions, field) do
    transactions
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
