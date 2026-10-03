defmodule TuistWeb.RunnerCacheMastersController do
  @moduledoc """
  `GET /api/internal/runners/cache-masters`: the cache-volume masters a macOS
  runner host should prefetch, for its converge worker.

  Authentication: the host presents a token for its own per-machine
  `tart-kubelet-<machine>` ServiceAccount, minted for the `tuist-runner-host`
  audience. The server validates it with a TokenReview and answers for the Node
  the ServiceAccount names, never one the request names. A runner Pod's token
  carries the dispatch audience and is refused here, because the response holds
  download URLs for every account on the host's fleet.
  """
  use TuistWeb, :controller

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.VolumePrefetch

  def index(conn, _params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, %{namespace: namespace, name: name}} <- K8sClient.create_runner_host_token_review(token),
         {:ok, node_name} <- VolumePrefetch.node_for_service_account(namespace, name) do
      masters =
        Enum.map(VolumePrefetch.for_node(node_name), fn master ->
          Map.take(master, [:account_id, :volume, :generation, :digest, :content_digest, :download_url])
        end)

      json(conn, %{masters: masters})
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
