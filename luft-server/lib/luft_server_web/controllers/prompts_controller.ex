defmodule LuftServerWeb.PromptsController do
  use LuftServerWeb, :controller

  alias LuftServer.Prompts
  alias LuftServer.Tuist.Scope

  plug :load_scope

  def index(conn, _params) do
    scope = conn.assigns.prompt_scope

    json(conn, %{
      prompts: Enum.map(Prompts.list(scope.organization_id), &serialize/1),
      can_edit: scope.can_create_threads
    })
  end

  def show(conn, %{"name" => name}) do
    case Prompts.get(conn.assigns.prompt_scope.organization_id, name) do
      nil -> error(conn, :not_found)
      prompt -> json(conn, %{prompt: serialize(prompt)})
    end
  end

  def update(conn, %{"name" => name}) do
    scope = conn.assigns.prompt_scope

    if scope.can_create_threads do
      case Prompts.put(
             conn.assigns.session.user_sub,
             scope.organization_id,
             name,
             conn.body_params
           ) do
        {:ok, prompt} -> json(conn, %{prompt: serialize(prompt)})
        {:error, reason} -> error(conn, reason)
      end
    else
      error(conn, :forbidden)
    end
  end

  def delete(conn, %{"name" => name}) do
    scope = conn.assigns.prompt_scope

    if scope.can_create_threads do
      {:ok, :ok} = Prompts.delete(conn.assigns.session.user_sub, scope.organization_id, name)
      send_resp(conn, 204, "")
    else
      error(conn, :forbidden)
    end
  end

  defp load_scope(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Scope.load(conn.assigns.session, conn.path_params["account_handle"]) do
      {:ok, %Scope{organization_id: id} = scope} when is_integer(id) ->
        assign(conn, :prompt_scope, scope)

      {:ok, _personal} ->
        conn |> error(:not_found) |> halt()

      {:error, reason} ->
        conn |> error(reason) |> halt()
    end
  end

  defp serialize(prompt),
    do:
      Map.take(prompt, [:name, :title, :body, :updated_at])
      |> Map.put(:standard, Prompts.standard?(prompt.name))

  defp error(conn, reason) do
    status =
      case reason do
        :unauthorized -> :unauthorized
        :not_found -> :not_found
        :forbidden -> :forbidden
        :invalid_prompt -> :unprocessable_entity
        _ -> :service_unavailable
      end

    conn |> put_status(status) |> json(%{code: reason})
  end
end
