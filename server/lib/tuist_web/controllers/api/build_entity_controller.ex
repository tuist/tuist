defmodule TuistWeb.API.BuildEntityController do
  @moduledoc false

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Params
  alias Tuist.BuildEntities.QueryLimitError

  defmacro __using__(opts) do
    key = Keyword.fetch!(opts, :resource)

    quote do
      use OpenApiSpex.ControllerSpecs
      use TuistWeb, :controller

      alias TuistWeb.API.BuildEntityController
      alias TuistWeb.API.Schemas.BuildEntity

      @resource TuistWeb.API.BuildEntityResources.fetch!(unquote(key))

      plug(TuistWeb.Plugs.CastAndValidate,
        json_render_error_v2: true,
        render_error: TuistWeb.RenderAPIErrorPlug
      )

      plug(TuistWeb.Plugs.LoaderPlug)
      plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

      tags [@resource.title]
      operation(:index, BuildEntity.operation(:index, @resource))
      operation(:show, BuildEntity.operation(:show, @resource))
      operation(:history, BuildEntity.operation(:history, @resource))

      def index(conn, _params), do: BuildEntityController.run(conn, :index, @resource)
      def show(conn, _params), do: BuildEntityController.run(conn, :show, @resource)
      def history(conn, _params), do: BuildEntityController.run(conn, :history, @resource)
    end
  end

  def run(%{assigns: %{selected_project: project}} = conn, action, resource) do
    with true <- project.build_system == resource.system,
         {:ok, opts} <- Params.parse(conn.params),
         {:ok, result} <- query(action, project.id, resource, conn.params, opts) do
      Phoenix.Controller.json(conn, result)
    else
      {:error, message} when is_binary(message) ->
        conn |> Plug.Conn.put_status(:bad_request) |> Phoenix.Controller.json(%{message: message})

      _ ->
        conn |> Plug.Conn.put_status(:not_found) |> Phoenix.Controller.json(%{message: "Not found in this project."})
    end
  rescue
    QueryLimitError ->
      conn
      |> Plug.Conn.put_status(:service_unavailable)
      |> Phoenix.Controller.json(%{message: "The query exceeded analytics limits. Please try again later."})
  end

  defp query(:index, project_id, resource, _params, opts) do
    {entries, meta} = BuildEntities.list(project_id, resource.system, resource.kind, opts)
    {:ok, %{resource.plural => entries, :pagination_metadata => meta}}
  end

  defp query(action, project_id, resource, params, opts) do
    id = Map.get(params, resource.id_param) || Map.get(params, Atom.to_string(resource.id_param))

    with {:ok, entity} <- BuildEntities.get(project_id, resource.system, resource.kind, id) do
      case action do
        :show ->
          analytics = BuildEntities.analytics(project_id, resource.system, resource.kind, id, opts)
          {:ok, %{resource.singular => entity, :analytics => analytics}}

        :history ->
          {entries, meta} = BuildEntities.history(project_id, resource.system, resource.kind, id, opts)
          {:ok, %{resource.history_key => entries, :pagination_metadata => meta}}
      end
    end
  end
end
