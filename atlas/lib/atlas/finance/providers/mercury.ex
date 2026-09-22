defmodule Atlas.Finance.Providers.Mercury do
  @moduledoc false

  alias Atlas.Finance.Account
  alias Atlas.Finance.Providers.Helpers

  require Logger

  @base_url "https://api.mercury.com/api/v1"
  @page_size 1000
  @receive_timeout 20_000
  @recent_backfill_days 30
  @zero Decimal.new("0")
  @credit_kinds ~w(
    card_international_transaction_fee_rebate
    card_international_transaction_fee_rebate_reversal
    check_deposit
    credit_card_credit
    currency_cloud_return
    debit_card_credit
    incoming_domestic_wire
    incoming_international_wire
  )
  @debit_kinds ~w(
    billing_engine_subscription_fee
    card_international_transaction_fee
    card_international_transaction_fee_reversal
    credit_card_transaction
    debit_card_transaction
    expense_reimbursement
    exogenous_wire_drawdown
    external_transfer
    outgoing_payment
    personal_banking_subscription_fee
    wire_fee
  )
  @non_cash_statuses ~w(blocked cancelled failed pending)
  @non_runway_kinds ~w(internal_transfer treasury_transfer)

  def describe_source(config) do
    case get(config, "/organization", []) do
      {:ok, organization} ->
        {:ok,
         %{
           external_id: Helpers.presence(organization["id"]) || Helpers.presence(organization["organizationId"]),
           name:
             Helpers.presence(organization["legalBusinessName"]) ||
               Helpers.presence(organization["name"]) ||
               config.name,
           metadata:
             Helpers.compact_map(%{
               "dba_names" => organization["dbaNames"] || organization["dbas"],
               "ein" => organization["ein"],
               "legal_business_name" => organization["legalBusinessName"]
             })
         }}

      {:error, {:http, 404, _body}} ->
        describe_source_from_accounts(config)

      error ->
        error
    end
  end

  def list_accounts(config) do
    fetch_accounts(config, nil, [])
  end

  def list_transactions(config, account, opts \\ [])

  def list_transactions(_config, %Account{external_id: nil}, _opts), do: {:ok, %{transactions: [], next_cursor: nil}}

  def list_transactions(config, %Account{} = account, opts) do
    now = Keyword.fetch!(opts, :now)
    synced_after = Keyword.fetch!(opts, :synced_after)
    start_datetime = backfill_start(synced_after, now)

    with {:ok, transactions} <-
           fetch_transactions(config, account.external_id, start_datetime, now, 0, []) do
      {:ok, %{transactions: transactions, next_cursor: now}}
    end
  end

  defp describe_source_from_accounts(config) do
    case list_accounts(config) do
      {:ok, [first_account | _rest]} ->
        {:ok,
         %{
           external_id: first_account.external_id,
           name: get_in(first_account.metadata, ["legal_business_name"]) || config.name,
           metadata: Helpers.compact_map(%{"inferred_from_account" => true})
         }}

      {:ok, []} ->
        {:ok, %{external_id: nil, name: config.name, metadata: %{"inferred_from_account" => true}}}

      error ->
        error
    end
  end

  defp fetch_accounts(config, cursor, accounts) do
    params =
      [limit: @page_size, order: "asc"]
      |> maybe_add_param(:start_after, cursor)

    case get(config, "/accounts", params) do
      {:ok, %{"accounts" => fetched_accounts} = body} when is_list(fetched_accounts) ->
        accounts = accounts ++ Enum.map(fetched_accounts, &normalize_account/1)

        get_in(body, ["page", "nextPage"])
        |> Helpers.presence()
        |> case do
          nil -> {:ok, accounts}
          next_cursor -> fetch_accounts(config, next_cursor, accounts)
        end

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      error ->
        error
    end
  end

  defp fetch_transactions(config, account_id, start_datetime, end_datetime, offset, transactions) do
    params = [
      limit: @page_size,
      offset: offset,
      order: "asc",
      start: DateTime.to_iso8601(start_datetime),
      end: DateTime.to_iso8601(end_datetime)
    ]

    case get(config, "/account/#{account_id}/transactions", params) do
      {:ok, %{"transactions" => fetched_transactions} = body} when is_list(fetched_transactions) ->
        normalized_transactions = Enum.map(fetched_transactions, &normalize_transaction/1)
        transactions = transactions ++ normalized_transactions
        fetched_count = length(fetched_transactions)

        cond do
          fetched_count == 0 ->
            {:ok, transactions}

          is_integer(body["total"]) and offset + fetched_count < body["total"] ->
            fetch_transactions(config, account_id, start_datetime, end_datetime, offset + fetched_count, transactions)

          fetched_count == @page_size ->
            fetch_transactions(config, account_id, start_datetime, end_datetime, offset + fetched_count, transactions)

          true ->
            {:ok, transactions}
        end

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      error ->
        error
    end
  end

  defp normalize_account(account) do
    currency = Helpers.presence(account["currency"]) || "USD"
    kind = normalize_kind(account["kind"]) || "bank_account"
    subtype = normalize_kind(account["type"])

    %{
      external_id: Helpers.presence(account["id"]),
      name:
        Helpers.presence(account["nickname"]) ||
          Helpers.presence(account["name"]) ||
          Helpers.presence(account["legalBusinessName"]) ||
          "Mercury account",
      account_type: kind,
      account_subtype: subtype,
      currency: currency,
      iban: nil,
      bic: nil,
      main: subtype == "mercury",
      status: normalize_status(account["status"]) || "active",
      balance_value: Helpers.decimal(account["currentBalance"]),
      balance_currency: currency,
      available_balance_value: Helpers.decimal(account["availableBalance"]),
      available_balance_currency: currency,
      metadata:
        Helpers.compact_map(%{
          "account_number_last4" => last4(account["accountNumber"]),
          "can_receive_transactions" => account["canReceiveTransactions"],
          "created_at" => account["createdAt"],
          "dashboard_link" => account["dashboardLink"],
          "legal_business_name" => account["legalBusinessName"],
          "routing_number" => account["routingNumber"],
          "type" => account["type"]
        })
    }
  end

  defp normalize_transaction(transaction) do
    amount = Helpers.decimal(transaction["amount"]) || @zero
    kind = normalize_kind(transaction["kind"]) || "transaction"
    status = normalize_status(transaction["status"]) || "sent"
    amount_currency = Helpers.presence(transaction["currency"]) || "USD"
    {local_amount_value, local_amount_currency} = local_amount(transaction["currencyExchangeInfo"], amount_currency)
    fee_value = Helpers.decimal(get_in(transaction, ["currencyExchangeInfo", "feeAmount"]))
    booked_at = booked_at(transaction)

    %{
      external_id: Helpers.presence(transaction["id"]),
      status: status,
      direction: normalize_direction(amount, kind),
      kind: kind,
      counterparty_name: counterparty_name(transaction),
      description: description(transaction),
      reference: reference(transaction),
      amount_value: Decimal.abs(amount),
      amount_currency: amount_currency,
      local_amount_value: local_amount_value,
      local_amount_currency: local_amount_currency,
      fee_value: fee_value,
      fee_currency: if(!is_nil(fee_value), do: amount_currency),
      running_balance_value: nil,
      running_balance_currency: nil,
      booked_at: booked_at,
      settled_at: Helpers.datetime(transaction["postedAt"]),
      provider_updated_at: Helpers.datetime(transaction["createdAt"]),
      affects_cash_balance: cash_balance_status?(status),
      affects_runway: runway_relevant?(status, kind),
      metadata: transaction_metadata(transaction),
      raw: transaction
    }
  end

  defp counterparty_name(transaction) do
    Helpers.presence(transaction["counterpartyName"]) || Helpers.presence(transaction["counterpartyNickname"])
  end

  defp description(transaction) do
    Helpers.presence(transaction["note"]) ||
      Helpers.presence(transaction["externalMemo"]) ||
      Helpers.presence(transaction["bankDescription"])
  end

  defp reference(transaction) do
    Helpers.presence(transaction["trackingNumber"]) ||
      Helpers.presence(transaction["requestId"]) ||
      Helpers.presence(transaction["checkNumber"])
  end

  defp booked_at(transaction), do: Helpers.datetime(transaction["postedAt"] || transaction["createdAt"])

  defp cash_balance_status?(status), do: status not in @non_cash_statuses

  defp runway_relevant?(status, kind) do
    cash_balance_status?(status) and kind not in @non_runway_kinds
  end

  defp transaction_metadata(transaction) do
    Helpers.compact_map(%{
      "account_id" => transaction["accountId"],
      "category_data" => transaction["categoryData"],
      "check_number" => transaction["checkNumber"],
      "counterparty_id" => transaction["counterpartyId"],
      "details" => transaction["details"],
      "failed_at" => transaction["failedAt"],
      "kind" => transaction["kind"],
      "mercury_category" => transaction["mercuryCategory"],
      "reason_for_failure" => transaction["reasonForFailure"],
      "request_id" => transaction["requestId"],
      "tracking_number" => transaction["trackingNumber"]
    })
  end

  defp local_amount(nil, _amount_currency), do: {nil, nil}

  defp local_amount(exchange_info, amount_currency) when is_map(exchange_info) do
    from_currency = Helpers.presence(exchange_info["convertedFromCurrency"])
    to_currency = Helpers.presence(exchange_info["convertedToCurrency"])
    from_amount = Helpers.decimal(exchange_info["convertedFromAmount"])
    to_amount = Helpers.decimal(exchange_info["convertedToAmount"])

    cond do
      from_currency == nil or to_currency == nil ->
        {nil, nil}

      to_currency == amount_currency ->
        {from_amount, from_currency}

      from_currency == amount_currency ->
        {to_amount, to_currency}

      true ->
        {nil, nil}
    end
  end

  defp local_amount(_exchange_info, _amount_currency), do: {nil, nil}

  defp normalize_direction(amount, kind) do
    case inferred_direction(kind) do
      nil ->
        case Decimal.compare(amount, @zero) do
          :lt -> "debit"
          :gt -> "credit"
          :eq -> "debit"
        end

      direction ->
        direction
    end
  end

  defp inferred_direction(kind) when kind in @credit_kinds, do: "credit"
  defp inferred_direction(kind) when kind in @debit_kinds, do: "debit"
  defp inferred_direction(_kind), do: nil

  defp normalize_status(nil), do: nil

  defp normalize_status(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_status(value), do: value |> to_string() |> normalize_status()

  defp normalize_kind(nil), do: nil

  defp normalize_kind(value) when is_binary(value) do
    value
    |> String.trim()
    |> Macro.underscore()
  end

  defp normalize_kind(value), do: value |> to_string() |> normalize_kind()

  defp backfill_start(%DateTime{} = synced_after, %DateTime{} = now) do
    recent_start = DateTime.add(now, -@recent_backfill_days, :day)

    case DateTime.compare(synced_after, recent_start) do
      :lt -> synced_after
      :eq -> recent_start
      :gt -> recent_start
    end
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: params ++ [{key, value}]

  defp last4(value) when is_binary(value) do
    if String.length(value) > 4, do: String.slice(value, -4, 4), else: value
  end

  defp last4(_value), do: nil

  defp get(config, path, params) do
    request =
      Req.new(
        url: url(config, path),
        auth: {:bearer, config[:api_token]},
        receive_timeout: receive_timeout(config),
        headers: [{"accept", "application/json"}]
      )
      |> Req.merge(params: params)

    case Req.get(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Mercury request failed: status=#{status} body=#{inspect(body)}")
        {:error, {:http, status, body}}

      {:error, reason} ->
        Logger.warning("Mercury transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp base_url(config), do: String.trim_trailing(config[:base_url] || @base_url, "/")

  defp url(config, path) do
    config
    |> base_url()
    |> URI.new!()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp receive_timeout(config) do
    case config[:receive_timeout] do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _other -> @receive_timeout
    end
  end
end
