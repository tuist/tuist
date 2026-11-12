defmodule Pulse.Errors.ProjectionCursor do
  @moduledoc false
  alias Plug.Crypto.MessageVerifier
  alias Pulse.Alerting.Canonical
  alias Pulse.Runtime

  # A monitoring cursor is durable until its advertised replay floor passes it,
  # not an expiring session. Bind both scope and operation to its authentication.
  def seal(ref, tenant, project, kind) do
    Canonical.encode(%{"scope" => [tenant, project, Atom.to_string(kind)], "ref" => ref})
    |> MessageVerifier.sign(secret())
  end

  def open(nil, _tenant, _project, _kind), do: {:ok, nil}

  def open(token, tenant, project, kind) when is_binary(token) and byte_size(token) <= 4096 do
    scope = [tenant, project, Atom.to_string(kind)]

    with {:ok, bytes} <- MessageVerifier.verify(token, secret()),
         {:ok, %{"scope" => ^scope, "ref" => ref}} when is_map(ref) <- Pulse.JSON.decode(bytes) do
      {:ok, ref}
    else
      _ -> {:error, :reset_required}
    end
  end

  def open(_, _, _, _), do: {:error, :reset_required}

  defp secret do
    secret = Runtime.fetch_env!(:pulse, PulseWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, "pulse-error-projection-v1:" <> secret)
  end
end
