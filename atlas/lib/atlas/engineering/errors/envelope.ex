defmodule Atlas.Engineering.Errors.Envelope do
  @moduledoc """
  Parses the Sentry envelope wire format.

  Spec: <https://develop.sentry.dev/sdk/data-model/envelopes/>.
  """

  defmodule Item do
    @moduledoc false
    defstruct [:type, :headers, :payload]
  end

  def parse(body) when is_binary(body) do
    case decode_line(body) do
      {:ok, header, rest} ->
        with {:ok, items} <- decode_items(rest, []) do
          {:ok, %{header: header, items: items}}
        end

      :error ->
        {:error, :invalid_envelope}
    end
  end

  defp decode_items("", acc), do: {:ok, Enum.reverse(acc)}
  defp decode_items("\n", acc), do: {:ok, Enum.reverse(acc)}

  defp decode_items(rest, acc) do
    with {:ok, item_header, rest} <- decode_line(rest),
         {:ok, item, rest} <- decode_item_payload(item_header, rest) do
      decode_items(rest, [item | acc])
    else
      _ -> {:error, :invalid_item}
    end
  end

  defp decode_item_payload(header, rest) do
    case header["length"] do
      length when is_integer(length) and length >= 0 ->
        take_by_length(header, rest, length)

      _ ->
        take_by_newline(header, rest)
    end
  end

  defp take_by_length(header, rest, length) do
    case rest do
      <<payload::binary-size(^length), rest_after::binary>> ->
        item = %Item{type: header["type"], headers: header, payload: payload}
        {:ok, item, strip_leading_newline(rest_after)}

      _ ->
        :error
    end
  end

  defp take_by_newline(header, rest) do
    case :binary.split(rest, "\n") do
      [payload, tail] ->
        item = %Item{type: header["type"], headers: header, payload: payload}
        {:ok, item, tail}

      [payload] ->
        item = %Item{type: header["type"], headers: header, payload: payload}
        {:ok, item, ""}
    end
  end

  defp strip_leading_newline(<<"\n", rest::binary>>), do: rest
  defp strip_leading_newline(rest), do: rest

  defp decode_line(binary) do
    case :binary.split(binary, "\n") do
      [line, rest] -> decode_json(line, rest)
      [line] -> decode_json(line, "")
    end
  end

  defp decode_json("", _rest), do: :error

  defp decode_json(line, rest) do
    case Jason.decode(line) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded, rest}
      _ -> :error
    end
  end
end
