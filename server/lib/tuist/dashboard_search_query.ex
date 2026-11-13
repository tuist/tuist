defmodule Tuist.DashboardSearchQuery do
  @moduledoc false

  @keys ~w(is project branch commit status date pr)
  @types ~w(page project test-case test-run build preview)

  def parse(raw) do
    with {:ok, tokens} <- tokenize(String.graphemes(raw), [], "", false, false) do
      Enum.reduce_while(tokens, {:ok, %{terms: [], filters: %{}}}, &token/2)
    end
  end

  defp tokenize([], _, _, true, _), do: {:error, "Close the quoted search value."}
  defp tokenize([], tokens, current, false, literal), do: {:ok, Enum.reverse(push(tokens, current, literal))}

  defp tokenize(["\\", char | rest], tokens, current, true, literal) when char in ["\\", "\""] do
    tokenize(rest, tokens, current <> char, true, literal)
  end

  defp tokenize(["\"" | rest], tokens, current, quoted, literal),
    do: tokenize(rest, tokens, current, not quoted, literal or current == "")

  defp tokenize([char | rest], tokens, current, false, literal) when char in [" ", "\n", "\r", "\t"] do
    tokenize(rest, push(tokens, current, literal), "", false, false)
  end

  defp tokenize([char | rest], tokens, current, quoted, literal),
    do: tokenize(rest, tokens, current <> char, quoted, literal)

  defp push(tokens, "", false), do: tokens
  defp push(tokens, current, literal), do: [{current, literal} | tokens]

  defp token({value, true}, {:ok, query}) do
    if String.trim(value) == "",
      do: {:halt, {:error, "Enter a nonempty quoted search term."}},
      else: {:cont, {:ok, %{query | terms: query.terms ++ [String.downcase(value)]}}}
  end

  defp token({value, false}, {:ok, query}) do
    case String.split(value, ":", parts: 2) do
      [key, value] when key not in ["https", "http"] ->
        cond do
          key not in @keys ->
            {:halt, {:error, "Unknown search filter. Use is, project, branch, commit, status, date or pr."}}

          Map.has_key?(query.filters, key) ->
            {:halt, {:error, "Use each search filter only once."}}

          true ->
            case validate(key, value) do
              {:ok, parsed} -> {:cont, {:ok, %{query | filters: Map.put(query.filters, key, parsed)}}}
              {:error, message} -> {:halt, {:error, message}}
            end
        end

      _ ->
        {:cont, {:ok, %{query | terms: query.terms ++ [String.downcase(value)]}}}
    end
  end

  defp validate("is", value) when value in @types, do: {:ok, String.replace(value, "-", "_")}
  defp validate("status", value) when value in ~w(failed passed running), do: {:ok, value}

  defp validate(key, value) when key in ["project", "branch"] do
    if String.trim(value) == "",
      do: {:error, "Enter a nonempty project or branch value."},
      else: {:ok, String.downcase(value)}
  end

  defp validate("commit", value) do
    if Regex.match?(~r/\A[0-9a-fA-F]{1,64}\z/, value),
      do: {:ok, String.downcase(value)},
      else: {:error, "Use a hexadecimal commit SHA prefix."}
  end

  defp validate("pr", value) do
    parsed = if Regex.match?(~r/\A#?[0-9]+\z/, value), do: Integer.parse(String.trim_leading(value, "#")), else: :error

    case parsed do
      {number, ""} when number > 0 and number <= 4_294_967_295 -> {:ok, number}
      _ -> {:error, "Use a positive pull request number, such as pr:123."}
    end
  end

  defp validate("date", value), do: date(value)
  defp validate(_, _), do: {:error, "Invalid or missing search filter value."}

  defp date("today"), do: day(Date.utc_today())
  defp date("yesterday"), do: day(Date.add(Date.utc_today(), -1))

  defp date(">" <> value) do
    with {:ok, date} <- iso_date(value), do: {:ok, {midnight(Date.add(date, 1)), nil}}
  end

  defp date("<" <> value) do
    with {:ok, date} <- iso_date(value), do: {:ok, {nil, midnight(date)}}
  end

  defp date(value) do
    case String.split(value, "..", parts: 2) do
      [first, last] ->
        with {:ok, first} <- iso_date(first), {:ok, last} <- iso_date(last) do
          if Date.after?(first, last),
            do: {:error, "The date range must start before it ends."},
            else: {:ok, {midnight(first), midnight(Date.add(last, 1))}}
        end

      [single] ->
        with {:ok, date} <- iso_date(single), do: day(date)
    end
  end

  defp iso_date(value) do
    parsed = if Regex.match?(~r/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/, value), do: Date.from_iso8601(value), else: :error

    case parsed do
      {:ok, date} -> {:ok, date}
      _ -> {:error, "Use today, yesterday, YYYY-MM-DD, >YYYY-MM-DD, <YYYY-MM-DD or YYYY-MM-DD..YYYY-MM-DD."}
    end
  end

  defp day(date), do: {:ok, {midnight(date), midnight(Date.add(date, 1))}}
  defp midnight(date), do: Date.to_iso8601(date) <> "T00:00:00Z"
end
