defmodule Pulse.Sentry.Envelope do
  @moduledoc "Byte-framed Sentry envelopes. Unsupported items are counted, never decoded."

  def decode(body) do
    with {:ok, headers, rest} <- header(body),
         {:ok, event, discarded} <- items(rest, nil, %{}, 0) do
      {:ok, headers, event, discarded}
    end
  end

  defp items(<<>>, event, discarded, _count), do: {:ok, event, discarded}
  defp items(_, _, _, count) when count >= 100, do: {:error, :too_many_items}

  defp items(body, event, discarded, count) do
    with {:ok, headers, rest} <- header(body),
         type when is_binary(type) <- headers["type"],
         {:ok, payload, rest} <- payload(rest, headers) do
      case type do
        "event" when event != nil ->
          {:error, :multiple_events}

        "event" ->
          decode_event(payload, rest, discarded, count)

        _ ->
          # Do not retain attacker-controlled type names as metric labels.
          items(rest, event, Map.update(discarded, type, 1, &(&1 + 1)), count + 1)
      end
    else
      _ -> {:error, :invalid_envelope}
    end
  end

  defp decode_event(payload, rest, discarded, count) when byte_size(payload) <= 1_048_576 do
    case Pulse.JSON.decode(payload) do
      {:ok, value} when is_map(value) -> items(rest, value, discarded, count + 1)
      _ -> {:error, :invalid_event}
    end
  end

  defp decode_event(_, _, _, _), do: {:error, :event_too_large}

  defp header(body) do
    {line, rest} = line(body)

    if byte_size(line) <= 16_384 do
      case Pulse.JSON.decode(line) do
        {:ok, value} when is_map(value) -> {:ok, value, rest}
        _ -> {:error, :invalid_envelope}
      end
    else
      {:error, :invalid_envelope}
    end
  end

  defp payload(body, %{"length" => size}) when is_integer(size) and size >= 0 and size <= byte_size(body) do
    <<payload::binary-size(^size), rest::binary>> = body

    case rest do
      <<>> -> {:ok, payload, <<>>}
      <<"\n", rest::binary>> -> {:ok, payload, rest}
      _ -> {:error, :invalid_envelope}
    end
  end

  defp payload(_body, %{"length" => _}), do: {:error, :invalid_envelope}

  defp payload(body, _headers) do
    {payload, rest} = line(body)
    {:ok, payload, rest}
  end

  defp line(body) do
    case :binary.split(body, "\n") do
      [line, rest] -> {line, rest}
      [line] -> {line, <<>>}
    end
  end
end
