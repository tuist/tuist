defmodule LuftServerWeb.CollectionsController do
  use LuftServerWeb, :controller

  alias LuftServer.Repo
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Tuist.Scope
  alias LuftServer.Workspaces.Behaviors

  def index(conn, _), do: perform(conn, :catalog, %{})
  def releases(conn, _), do: perform(conn, :releases, %{})
  def release(conn, _), do: perform(conn, :release, %{"hash" => conn.path_params["hash"]})
  def authoring(conn, _), do: perform(conn, :authoring, %{})
  def validate(conn, _), do: perform(conn, :validate, conn.body_params)
  def propose(conn, _), do: perform(conn, :propose, conn.body_params)
  def approve(conn, _), do: perform(conn, :approve, %{"hash" => conn.path_params["hash"]})
  def merge(conn, _), do: perform(conn, :merge, %{"hash" => conn.path_params["hash"]})
  def activate(conn, _), do: perform(conn, :activate, %{"hash" => conn.path_params["hash"]})

  def invoke(conn, _),
    do: perform(conn, :invoke, Map.put(conn.body_params, "method", conn.path_params["method"]))

  def query(conn, _),
    do:
      perform(
        conn,
        :query,
        Map.put(conn.body_params, "collection", conn.path_params["collection"])
      )

  def show(conn, _) do
    version =
      case conn.query_params["version"] do
        nil ->
          nil

        value ->
          case Integer.parse(value) do
            {n, ""} -> n
            _ -> :invalid
          end
      end

    perform(conn, :get, %{
      "collection" => conn.path_params["collection"],
      "id" => conn.path_params["record_id"],
      "version" => version
    })
  end

  def reference(conn, _) do
    perform(conn, :reference, %{
      "thread" => conn.path_params["id"],
      "message" => conn.path_params["message_id"]
    })
  end

  defp perform(conn, operation, body) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    result =
      with {:ok, scope} <- Scope.load(conn.assigns.session, conn.path_params["account_handle"]),
           {:ok, operation, body} <- reference(scope, operation, body) do
        Behaviors.for_scope(scope, operation, body)
      else
        {:error, :tuist_unavailable} -> {:error, :unavailable}
        _ -> {:error, :forbidden}
      end

    respond(conn, result)
  rescue
    _ -> respond(conn, {:error, :unavailable})
  end

  defp reference(scope, :reference, %{"thread" => thread, "message" => message}) do
    with {:ok, _} <- Threads.get(scope, thread),
         {:ok, message} <- Ecto.UUID.cast(message),
         %Message{kind: "record", record_reference: %{"model" => collection, "id" => id}} <-
           Repo.get_by(Message, thread_id: thread, id: message) do
      {:ok, :get, %{"collection" => collection, "id" => id}}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp reference(_, operation, body), do: {:ok, operation, body}

  defp respond(conn, {:ok, value}), do: json(conn, value)

  defp respond(conn, {:error, reason}) do
    status =
      case reason do
        :forbidden -> 403
        :not_found -> 404
        reason when reason in [:revision_conflict, :incompatible_release] -> 409
        :unavailable -> 503
        _ -> 422
      end

    conn
    |> put_status(status)
    |> json(%{
      error: %{
        code: reason |> Atom.to_string() |> String.upcase(),
        message: "Operation unavailable"
      }
    })
  end
end
