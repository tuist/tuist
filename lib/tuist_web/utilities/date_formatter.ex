defmodule TuistWeb.Utilities.DateFormatter do
  @moduledoc false
  def from_now(date) do
    case date |> Timex.from_now() |> String.split(" ") do
      [number, "month", relative] -> number <> "mo " <> relative
      [number, "months", relative] -> number <> "mo " <> relative
      [number, unit, relative] -> number <> String.at(unit, 0) <> " " <> relative
      _ -> Timex.from_now(date)
    end
  end
end
