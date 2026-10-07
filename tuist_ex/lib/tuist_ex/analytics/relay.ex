defmodule TuistEx.Analytics.Relay do
  @moduledoc false

  # Writes a child process's output to a device as it arrives, for
  # `System.cmd(..., into: Relay.new())`. The child's output comes in byte
  # chunks that can end in the middle of a UTF-8 character, and a device in
  # unicode mode (a terminal, or a pipe under a UTF-8 locale) raises on
  # anything that is not valid UTF-8. So the bytes of an unfinished character
  # wait for the next chunk, and bytes that can never form one are replaced.
  # A device in latin1 mode writes bytes as they are, so they go through
  # untouched; writing them in binary mode to a unicode device would encode
  # each byte again.

  defstruct device: :stdio

  def new(device \\ :stdio), do: %__MODULE__{device: device}

  @doc false
  def split_incomplete(data), do: split_incomplete(data, min(byte_size(data), 3))

  defp split_incomplete(data, 0), do: {data, ""}

  defp split_incomplete(data, n) do
    complete = byte_size(data) - n
    lead = :binary.at(data, complete)

    cond do
      lead in 0x80..0xBF ->
        split_incomplete(data, n - 1)

      n < sequence_length(lead) ->
        {binary_part(data, 0, complete), binary_part(data, complete, n)}

      true ->
        {data, ""}
    end
  end

  defp sequence_length(lead) when lead in 0xC0..0xDF, do: 2
  defp sequence_length(lead) when lead in 0xE0..0xEF, do: 3
  defp sequence_length(lead) when lead in 0xF0..0xF7, do: 4
  defp sequence_length(_lead), do: 1

  defimpl Collectable do
    alias TuistEx.Analytics.Relay

    def into(%Relay{device: device} = relay) do
      if encoding(device) == :latin1 do
        {:ok, &binary_collector(device, relay, &1, &2)}
      else
        {"", &unicode_collector(device, relay, &1, &2)}
      end
    end

    defp binary_collector(device, _relay, :ok, {:cont, chunk}), do: IO.binwrite(device, chunk)
    defp binary_collector(_device, relay, :ok, :done), do: relay
    defp binary_collector(_device, _relay, _acc, :halt), do: :ok

    defp unicode_collector(device, _relay, pending, {:cont, chunk}) do
      {complete, pending} = Relay.split_incomplete(pending <> chunk)
      write(device, complete)
      pending
    end

    defp unicode_collector(device, relay, pending, :done) do
      write(device, pending)
      relay
    end

    defp unicode_collector(_device, _relay, _pending, :halt), do: :ok

    defp write(_device, ""), do: :ok

    defp write(device, data) do
      data = if String.valid?(data), do: data, else: String.replace_invalid(data)
      IO.write(device, data)
    end

    defp encoding(:stdio), do: encoding(:standard_io)
    defp encoding(:stderr), do: encoding(:standard_error)

    defp encoding(device) do
      case :io.getopts(device) do
        opts when is_list(opts) -> Keyword.get(opts, :encoding, :unicode)
        _ -> :unicode
      end
    end
  end
end
