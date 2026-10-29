defmodule TuistEx.Analytics.Report do
  @moduledoc false

  # What every report needs, whatever it reports.

  @doc "A new report id: a random, version 4, UUID."
  def id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b"
    |> :io_lib.format([a, b, c, d, e])
    |> IO.iodata_to_binary()
  end

  @doc "Says why a report was not sent, when `TUIST_DEBUG=1` asks to hear it."
  def debug(message) do
    if System.get_env("TUIST_DEBUG") == "1", do: IO.puts(:stderr, message)
    :ok
  end
end
