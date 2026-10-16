defmodule Atlas.TimeOff.PublicHolidays do
  @moduledoc "Fetches national and matching subdivision public holidays from Nager.Date."

  def fetch(location, year) do
    case Req.get("https://date.nager.at/api/v3/PublicHolidays/#{year}/#{location.country_code}",
           receive_timeout: 15_000,
           retry: false,
           redirect: false
         ) do
      {:ok, %{status: 200, body: holidays}} when is_list(holidays) ->
        normalize(holidays, location, year)

      _ ->
        {:error, :holiday_provider_unavailable}
    end
  end

  defp normalize(holidays, location, year) do
    Enum.reduce_while(holidays, {:ok, []}, fn holiday, {:ok, acc} ->
      case normalize_holiday(holiday, location, year) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        :skip -> {:cont, {:ok, acc}}
        :error -> {:halt, {:error, :invalid_holiday_response}}
      end
    end)
  end

  defp normalize_holiday(%{"date" => date, "name" => name, "types" => types} = holiday, location, year)
       when is_binary(date) and is_binary(name) and is_list(types) do
    with {:ok, parsed} <- Date.from_iso8601(date),
         true <- parsed.year == year,
         true <- is_boolean(holiday["global"]),
         true <- is_nil(holiday["counties"]) or is_list(holiday["counties"]) do
      applies? = holiday["global"] or location.subdivision_code in (holiday["counties"] || [])

      if "Public" in types and applies? do
        {:ok, %{name: name, date: parsed}}
      else
        :skip
      end
    else
      _ -> :error
    end
  end

  defp normalize_holiday(_holiday, _location, _year), do: :error
end
