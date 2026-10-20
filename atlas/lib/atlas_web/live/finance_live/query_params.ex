defmodule AtlasWeb.FinanceLive.QueryParams do
  @moduledoc false

  alias AtlasWeb.Utilities.Query
  alias Noora.Filter

  @transactions_page_size 25
  @transactions_date_range_prefix "transactions"
  @transactions_page_param "transactions-page"
  @legacy_filter_ids ~w(provider atlas_account_id source_key account_id currency direction status kind category_id)

  def finance_query_params(search, filters, date_range_preset, date_range_period) do
    filters
    |> Filter.Operations.encode_filters_to_query()
    |> Query.put_present("search", search)
    |> Map.merge(date_range_query_params(date_range_preset, date_range_period))
  end

  def transaction_filters(search, filters, period, page \\ 1) do
    {date_from, date_to} = normalize_period(period)

    [
      page: page,
      page_size: @transactions_page_size,
      provider: filter_value(filters, "provider"),
      source_key: filter_value(filters, "source_key"),
      atlas_account_id: filter_value(filters, "atlas_account_id"),
      account_id: filter_value(filters, "account_id"),
      currency: filter_value(filters, "currency"),
      direction: filter_value(filters, "direction"),
      status: filter_value(filters, "status"),
      kind: filter_value(filters, "kind"),
      category_id: filter_value(filters, "category_id"),
      date_from: date_from,
      date_to: date_to,
      query: normalize_param(search)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  def normalize_finance_params(params) do
    params
    |> Query.copy_legacy_search("query", "search")
    |> Query.copy_legacy_filters(@legacy_filter_ids, params)
    |> maybe_copy_legacy_date_range_params(params["date_from"], params["date_to"])
  end

  def transactions_date_picker_params(params) do
    preset = normalize_param(params["#{@transactions_date_range_prefix}-date-range"])

    cond do
      is_nil(preset) ->
        %{preset: nil, period: nil}

      preset == "custom" ->
        custom_period(params, preset)

      true ->
        %{preset: preset, period: transactions_period_for_preset(preset)}
    end
  end

  def date_range_query_params(nil, _period), do: %{}

  def date_range_query_params("custom", {start_datetime, end_datetime}) do
    %{
      "#{@transactions_date_range_prefix}-date-range" => "custom",
      "#{@transactions_date_range_prefix}-start-date" => DateTime.to_iso8601(start_datetime),
      "#{@transactions_date_range_prefix}-end-date" => DateTime.to_iso8601(end_datetime)
    }
  end

  def date_range_query_params(preset, _period) do
    %{"#{@transactions_date_range_prefix}-date-range" => preset}
  end

  def current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  def filter_value(filters, filter_id) do
    filters
    |> Enum.find(&(&1.id == filter_id))
    |> case do
      nil -> nil
      filter -> normalize_param(filter.value)
    end
  end

  def normalize_param(value), do: Query.present_string(value)
  def transactions_page_param, do: @transactions_page_param

  defp maybe_copy_legacy_date_range_params(params, date_from, date_to) do
    cond do
      Map.has_key?(params, "#{@transactions_date_range_prefix}-date-range") ->
        params

      blank?(date_from) or blank?(date_to) ->
        params

      true ->
        case {parse_date_from(date_from), parse_date_to(date_to)} do
          {%DateTime{} = start_datetime, %DateTime{} = end_datetime} ->
            params
            |> Map.put("#{@transactions_date_range_prefix}-date-range", "custom")
            |> Map.put("#{@transactions_date_range_prefix}-start-date", DateTime.to_iso8601(start_datetime))
            |> Map.put("#{@transactions_date_range_prefix}-end-date", DateTime.to_iso8601(end_datetime))

          _other ->
            params
        end
    end
  end

  defp custom_period(params, preset) do
    case {
      parse_date_from(params["#{@transactions_date_range_prefix}-start-date"]),
      parse_date_to(params["#{@transactions_date_range_prefix}-end-date"])
    } do
      {%DateTime{} = start_datetime, %DateTime{} = end_datetime} ->
        %{preset: preset, period: {start_datetime, end_datetime}}

      _other ->
        %{preset: nil, period: nil}
    end
  end

  defp transactions_period_for_preset(preset) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    start_datetime =
      case preset do
        "last-7-days" -> DateTime.add(now, -7, :day)
        "last-30-days" -> DateTime.add(now, -30, :day)
        "last-90-days" -> DateTime.add(now, -90, :day)
        "last-12-months" -> DateTime.add(now, -365, :day)
        _other -> DateTime.add(now, -30, :day)
      end

    {start_datetime, now}
  end

  defp normalize_period(nil), do: {nil, nil}
  defp normalize_period({start_datetime, end_datetime}), do: {start_datetime, end_datetime}

  defp parse_date_from(nil), do: nil
  defp parse_date_from(value), do: parse_date(value, ~T[00:00:00])

  defp parse_date_to(nil), do: nil
  defp parse_date_to(value), do: parse_date(value, ~T[23:59:59])

  defp parse_date(value, fallback_time) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        DateTime.new!(date, fallback_time, "Etc/UTC")

      {:error, _reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          {:error, _reason} -> nil
        end
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
