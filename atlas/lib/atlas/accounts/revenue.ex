defmodule Atlas.Accounts.Revenue do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.ExchangeRates
  alias Atlas.Accounts.Snapshot
  alias Atlas.Accounts.Term
  alias Atlas.Repo

  require Logger

  def snapshot(opts \\ []) do
    accounts =
      Account
      |> where(
        [account],
        account.segment == :customer and
          (is_nil(account.status) or account.status != "churned") and
          is_nil(account.not_an_account_at)
      )
      |> preload(terms: ^latest_terms_query())
      |> Repo.all()

    term_events_by_account =
      accounts
      |> Enum.map(& &1.id)
      |> latest_term_events_by_account()

    exchange_rates =
      accounts
      |> snapshot_currencies()
      |> latest_exchange_rates(opts)
      |> case do
        {:ok, rates} ->
          rates

        {:error, reason} ->
          Logger.warning("Failed to load live ECB exchange rates for revenue snapshot: #{inspect(reason)}")
          nil
      end

    Snapshot.build(accounts, term_events_by_account, exchange_rates)
  end

  defp latest_term_events_by_account([]), do: %{}

  defp latest_term_events_by_account(account_ids) do
    Event
    |> where([event], event.account_id in ^account_ids and event.kind == "term" and event.source == "enterprise")
    |> order_by([event], desc: event.occurred_at)
    |> Repo.all()
    |> Enum.group_by(& &1.account_id)
    |> Map.new(fn {account_id, [latest_event | _rest]} -> {account_id, latest_event} end)
  end

  defp latest_terms_query do
    from(term in Term,
      order_by: [desc: term.start_date, desc: term.inserted_at]
    )
  end

  defp snapshot_currencies(accounts) do
    accounts
    |> Enum.flat_map(fn account ->
      [account.currency | Enum.map(Term.loaded(account), & &1.currency)]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.upcase/1)
    |> Enum.reject(&(&1 == "EUR"))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp latest_exchange_rates(currencies, opts) do
    client = exchange_rates_client(opts)
    client.latest_rates(currencies)
  end

  defp exchange_rates_client(opts) do
    Keyword.get(opts, :exchange_rates_client) ||
      :atlas
      |> Application.get_env(:accounts, [])
      |> Keyword.get(:exchange_rates_client, ExchangeRates)
  end
end
