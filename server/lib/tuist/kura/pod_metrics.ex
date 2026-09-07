defmodule Tuist.Kura.PodMetrics do
  @moduledoc """
  Reads one cache pod's Prometheus exposition over the in-cluster network.

  Pods are addressed through their StatefulSet's governing headless Service,
  which publishes not-ready addresses, so a pod that has stopped serving is
  still readable. The host is built from the `Server` row's
  `provisioner_node_ref` rather than from the requested name.
  """

  alias Tuist.Kura.Server
  alias Tuist.Repo

  @namespace "kura"
  @port 4000
  @path "/metrics"
  @receive_timeout to_timeout(second: 10)
  @pod_name_format ~r/\A[a-z0-9][a-z0-9-]*-\d{1,3}\z/

  @doc """
  Fetches the exposition text for `pod_name`, a StatefulSet pod name of the
  form `<provisioner_node_ref>-<ordinal>`.

  Returns `{:ok, body}`, or `{:error, :invalid_pod_name}`,
  `{:error, :not_found}` when no server owns the ref, or
  `{:error, {:unreachable, reason}}` / `{:error, {:unexpected_status, status}}`.
  """
  def fetch(pod_name) when is_binary(pod_name) do
    with {:ok, ref, ordinal} <- parse(pod_name),
         {:ok, server} <- fetch_server(ref) do
      get(url(server.provisioner_node_ref, ordinal))
    end
  end

  defp parse(pod_name) do
    if Regex.match?(@pod_name_format, pod_name) do
      {ordinal, ref_parts} = pod_name |> String.split("-") |> List.pop_at(-1)

      case Enum.join(ref_parts, "-") do
        "" -> {:error, :invalid_pod_name}
        ref -> {:ok, ref, String.to_integer(ordinal)}
      end
    else
      {:error, :invalid_pod_name}
    end
  end

  defp fetch_server(ref) do
    case Repo.get_by(Server, provisioner_node_ref: ref) do
      nil -> {:error, :not_found}
      %Server{} = server -> {:ok, server}
    end
  end

  defp url(ref, ordinal) do
    "http://#{ref}-#{ordinal}.#{ref}-headless.#{@namespace}.svc.cluster.local:#{@port}#{@path}"
  end

  defp get(url) do
    case Req.get(url, retry: false, receive_timeout: @receive_timeout) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, {:unreachable, reason}}
    end
  end
end
