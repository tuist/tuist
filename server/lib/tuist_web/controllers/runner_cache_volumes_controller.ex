defmodule TuistWeb.RunnerCacheVolumesController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.VolumePrefetch

  def authorize(conn, params) do
    with :ok <- authenticate(conn),
         {:ok, identity} <- CacheVolumes.allocate(params) do
      conn |> put_resp_header("cache-control", "no-store") |> json(identity)
    else
      {:error, :pending} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("retry-after", "1")
        |> put_status(425)
        |> json(%{error: "job execution pending"})

      # The capacity chosen for the job's copy exceeds what the host holds.
      {:error, :capacity} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(507)
        |> json(%{error: "capacity"})

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "cache volume unavailable"})
    end
  end

  def checkout(conn, params) do
    with :ok <- authenticate(conn),
         {:ok, checkout} <- CacheVolumes.allocate_checkout(params) do
      conn |> put_resp_header("cache-control", "no-store") |> json(checkout)
    else
      {:error, :pending} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("retry-after", "1")
        |> put_status(425)
        |> json(%{error: "job execution pending"})

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "checkout unavailable"})
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

  def image(conn, %{"node_name" => node, "id" => id} = params) do
    with :ok <- authenticate(conn),
         {:ok, result} <- CacheVolumes.image(node, id, params) do
      conn |> put_resp_header("cache-control", "no-store") |> json(result)
    else
      {:error, reason} when reason in [:conflict, :not_found] -> send_resp(conn, :conflict, "")
      _ -> send_resp(conn, :forbidden, "")
    end
  end

  def image(conn, _), do: send_resp(conn, :bad_request, "")

  # The custom HEADs a Linux host should prefetch (`VolumePrefetch.for_node/2`).
  def masters(conn, %{"node_name" => node}) when is_binary(node) and node != "" do
    case authenticate(conn) do
      :ok ->
        masters =
          Enum.map(VolumePrefetch.for_node(node, :linux), fn master ->
            Map.take(master, [
              :kind,
              :id,
              :account_id,
              :scope,
              :generation,
              :image_digest,
              :content_digest,
              :volume_bytes,
              :head_size_bytes,
              :reason
            ])
          end)

        conn |> put_resp_header("cache-control", "no-store") |> json(%{masters: masters})

      _ ->
        send_resp(conn, :forbidden, "")
    end
  end

  def masters(conn, _), do: send_resp(conn, :bad_request, "")

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
