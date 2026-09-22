defmodule TuistWeb.RunnerCacheVolumesController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes

  def authorize(conn, params) do
    with :ok <- authenticate(conn),
         true <- Application.get_env(:tuist, :runner_linux_cache_volumes, false),
         {:ok, identity} <- CacheVolumes.allocate(params) do
      conn |> put_resp_header("cache-control", "no-store") |> json(identity)
    else
      _ -> conn |> put_status(:forbidden) |> json(%{error: "cache volume unavailable"})
    end
  end

  def report(conn, %{"node_name" => node, "id" => id} = params) do
    case authenticate(conn) do
      :ok ->
        case CacheVolumes.report(node, id, params) do
          {:ok, result} ->
            conn |> put_resp_header("cache-control", "no-store") |> json(result)

          {:error, :not_found} ->
            # Metadata is cascaded on account deletion. Agents still fence writers.
            action = if params["state"] == "deleted", do: "forget", else: "delete"
            conn |> put_resp_header("cache-control", "no-store") |> json(%{action: action})

          _ ->
            send_resp(conn, :forbidden, "")
        end

      _ ->
        send_resp(conn, :forbidden, "")
    end
  end

  def report(conn, _), do: send_resp(conn, :bad_request, "")

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{namespace: namespace, name: name}} <- K8sClient.create_controller_token_review(token),
         true <-
           namespace == Application.get_env(:tuist, :runner_cache_volumes_namespace, Environment.runners_namespace()),
         true <- name == Application.get_env(:tuist, :runner_cache_volumes_sa_name, "tuist-runner-cache-volumes") do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end
end
