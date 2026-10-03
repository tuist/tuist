defmodule Atlas.Finance.Config do
  @moduledoc false

  alias Atlas.Accounts.Amounts

  @default_initial_lookback_days 365
  @default_report_currency "EUR"
  @default_runway_window_days 180
  @default_sync_overlap_minutes 5
  @provider_keys ~w(qonto mercury)a

  def configured_sources(config \\ finance_config()) do
    config
    |> Keyword.get(:sources, [])
    |> Enum.map(&normalize_source/1)
    |> Enum.reject(&is_nil/1)
  end

  def configured_source_keys(config \\ finance_config()) do
    config
    |> configured_sources()
    |> Enum.map(& &1.key)
  end

  def fetch_source(source_key, config \\ finance_config()) when is_binary(source_key) do
    config
    |> configured_sources()
    |> Enum.find(&(&1.key == source_key))
    |> case do
      nil -> {:error, :source_not_configured}
      source -> {:ok, source}
    end
  end

  def report_currency(config \\ finance_config()) do
    config
    |> Keyword.get(:report_currency, @default_report_currency)
    |> Amounts.normalize_currency()
    |> case do
      nil -> @default_report_currency
      currency -> currency
    end
  end

  def runway_window_days(config \\ finance_config()),
    do: positive_integer(Keyword.get(config, :runway_window_days), @default_runway_window_days)

  def initial_lookback_days(config \\ finance_config()),
    do: positive_integer(Keyword.get(config, :initial_lookback_days), @default_initial_lookback_days)

  def sync_overlap_seconds(config \\ finance_config()) do
    config
    |> Keyword.get(:sync_overlap_minutes, @default_sync_overlap_minutes)
    |> positive_integer(@default_sync_overlap_minutes)
    |> Kernel.*(60)
  end

  @doc """
  Names of our own legal entities. Transfers whose counterparty matches one of
  these are intercompany movements, not operating revenue/expense.
  """
  def internal_entity_names(config \\ finance_config()) do
    config
    |> Keyword.get(:internal_entity_names, [])
    |> List.wrap()
    |> Enum.map(&blank_to_nil/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  `internal_entity_names/1` normalized for case-insensitive counterparty
  matching. Shared by the sync flagging and the backfill migration so both use
  the same source of truth and rules.
  """
  def normalized_internal_entity_names(config \\ finance_config()) do
    config
    |> internal_entity_names()
    |> Enum.map(&normalize_entity_name/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Normalizes an entity/counterparty name for matching (trim + downcase)."
  def normalize_entity_name(nil), do: nil

  def normalize_entity_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  @doc """
  Whether a counterparty name denotes one of our own legal entities (an
  intercompany transfer). Matches by prefix so bank-appended detail still
  resolves — e.g. a SWIFT credit labelled `"Tuist Inc.\\n, 1111B S Governors
  Ave"` still matches the configured `"Tuist Inc."`. `normalized_names` must come
  from `normalized_internal_entity_names/1`.
  """
  def internal_counterparty?(counterparty_name, normalized_names) when is_list(normalized_names) do
    case normalize_entity_name(counterparty_name) do
      nil -> false
      normalized -> Enum.any?(normalized_names, &String.starts_with?(normalized, &1))
    end
  end

  defp finance_config, do: Application.get_env(:atlas, :finance, [])

  defp normalize_source(source) when is_list(source), do: source |> Map.new() |> normalize_source()

  defp normalize_source(%{} = source) do
    with source_key when is_binary(source_key) and source_key != "" <- blank_to_nil(source[:key]),
         provider when is_atom(provider) and not is_nil(provider) <- normalize_provider(source[:provider]) do
      Map.merge(source, %{
        key: source_key,
        provider: provider,
        name: blank_to_nil(source[:name]) || default_name(provider)
      })
    else
      _ -> nil
    end
  end

  defp normalize_source(_other), do: nil

  defp normalize_provider(provider) when provider in @provider_keys, do: provider
  defp normalize_provider(provider) when is_atom(provider), do: nil

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      "qonto" -> :qonto
      "mercury" -> :mercury
      _other -> nil
    end
  end

  defp normalize_provider(_provider), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp default_name(provider) do
    provider
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
