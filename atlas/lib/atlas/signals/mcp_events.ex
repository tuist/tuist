defmodule Atlas.Signals.MCPEvents do
  @moduledoc "Signed MCP event callbacks feeding the existing source admission boundary."

  alias Atlas.Repo
  alias Atlas.Signals
  alias Atlas.Signals.Source
  alias Atlas.Users.User

  # Returned only on creation. Persisted sources never contain this virtual field.
  def delivery(%Source{signing_secret: nil}), do: nil

  def delivery(source) do
    %{
      path: "/api/signals/#{source.id}/mcp-events",
      secret: "whsec_" <> Base.encode64(source.signing_secret)
    }
  end

  def receive_event(id, headers, raw_body) when is_binary(raw_body) and byte_size(raw_body) <= 12_000 do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Source{event_receiver: %{}, signing_secret: secret} = source when is_binary(secret) <- Repo.get(Source, id),
         {:ok, message_id} <- verify(headers, raw_body, secret),
         {:ok, %{} = payload} <- JSON.decode(raw_body) do
      admit(source, message_id, payload)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def receive_event(_id, _headers, _raw_body), do: {:error, :payload_too_large}

  defp verify(headers, body, secret) do
    with [id] <- values(headers, "webhook-id"),
         true <- byte_size(id) in 1..200 and not String.contains?(id, <<0>>),
         [timestamp] <- values(headers, "webhook-timestamp"),
         {seconds, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - seconds) <= 300,
         [signatures] <- values(headers, "webhook-signature"),
         true <- byte_size(signatures) <= 4096 do
      expected = "v1," <> Base.encode64(:crypto.mac(:hmac, :sha256, secret, "#{id}.#{timestamp}.#{body}"))

      if Enum.any?(String.split(signatures), &Plug.Crypto.secure_compare(&1, expected)),
        do: {:ok, id},
        else: {:error, :unauthorized}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp values(headers, name), do: for({^name, value} <- headers, do: value)

  # Verification precedes source enablement so enrollment cannot start work.
  defp admit(_source, _id, %{"type" => "verification", "challenge" => challenge})
       when is_binary(challenge) and byte_size(challenge) in 1..256, do: {:ok, %{challenge: challenge}}

  defp admit(source, id, %{"eventId" => id, "name" => name, "timestamp" => timestamp, "data" => data})
       when is_map(data) and is_binary(timestamp) do
    config = source.event_receiver
    correlation = data[config["correlation_field"]]

    if name == config["name"] and Enum.all?(config["match"], fn {key, value} -> data[key] === value end) and
         ((is_binary(correlation) and String.trim(correlation) != "") or is_integer(correlation)) do
      envelope = %{
        "external_id" => id,
        "correlation_key" => Base.encode16(:crypto.hash(:sha256, JSON.encode!([name, correlation])), case: :lower),
        "type" => name,
        "schema_version" => 1,
        "occurred_at" => timestamp,
        "title" => config["title"],
        "summary" => config["summary"],
        "subjects" => config["subjects"],
        "topics" => config["topics"],
        "data" => data
      }

      # Recheck the owner's current grants and the locked source before admission.
      case Repo.get(User, source.owner_id) do
        %User{} = actor -> Signals.ingest(actor, source.id, envelope, interface: "api")
        nil -> {:error, :unauthorized}
      end
    else
      {:error, :invalid_event}
    end
  end

  defp admit(_source, _id, _payload), do: {:error, :invalid_event}
end
