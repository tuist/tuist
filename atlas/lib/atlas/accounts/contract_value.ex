defmodule Atlas.Accounts.ContractValue do
  @moduledoc false

  alias Atlas.Accounts.Term

  def value(account, today \\ Date.utc_today()) do
    %{value: value, currency: currency} = source(account, today)
    {value, currency}
  end

  def source(account, today \\ Date.utc_today()) do
    case current_term(Term.loaded(account), today) do
      nil ->
        %{
          source: :account,
          value: account.current_value,
          currency: account.currency,
          term: nil
        }

      term ->
        %{
          source: :term,
          value: term.total,
          currency: present(term.currency) || account.currency,
          term: term
        }
    end
  end

  def current_term(terms, today \\ Date.utc_today())

  def current_term(terms, %Date{} = today) when is_list(terms) do
    terms = Enum.filter(terms, &usable_term?/1)

    Enum.find(terms, &active_term?(&1, today)) || nearest_term(terms, today)
  end

  def current_term(_terms, _today), do: nil

  # With nothing active, the nearest signed term describes the account better
  # than the furthest-future one, so upcoming terms win over terms that have
  # already run their course. Terms may reach us in any order.
  defp nearest_term(terms, today) do
    {upcoming, started} = Enum.split_with(terms, &upcoming_term?(&1, today))

    nearest_upcoming_term(upcoming) || most_recently_started_term(started)
  end

  defp nearest_upcoming_term([]), do: nil
  defp nearest_upcoming_term(terms), do: Enum.min_by(terms, & &1.start_date, Date)

  defp most_recently_started_term(terms) do
    case Enum.filter(terms, &match?(%Date{}, &1.start_date)) do
      [] -> List.first(terms)
      dated_terms -> Enum.max_by(dated_terms, & &1.start_date, Date)
    end
  end

  defp usable_term?(term), do: not is_nil(term.total)

  defp upcoming_term?(%{start_date: %Date{} = start_date}, today), do: Date.after?(start_date, today)
  defp upcoming_term?(_term, _today), do: false

  defp active_term?(term, today) do
    starts_on_or_before?(term.start_date, today) and ends_on_or_after?(term.end_date, today)
  end

  defp starts_on_or_before?(%Date{} = start_date, today), do: Date.compare(start_date, today) != :gt
  defp starts_on_or_before?(_start_date, _today), do: false

  defp ends_on_or_after?(nil, _today), do: true
  defp ends_on_or_after?(%Date{} = end_date, today), do: Date.compare(end_date, today) != :lt
  defp ends_on_or_after?(_end_date, _today), do: false

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(value), do: value
end
