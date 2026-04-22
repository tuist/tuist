defmodule Tuist.MCP.Tool do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.Projects

  # --- Macro ---

  defmacro __using__(opts) do
    authorize = Keyword.get(opts, :authorize)

    call_impl =
      case authorize do
        auth_opts when is_list(auth_opts) ->
          action = Keyword.fetch!(auth_opts, :action)
          category = Keyword.fetch!(auth_opts, :category)

          quote do
            @impl EMCP.Tool
            def call(conn, args) do
              Tuist.MCP.Tool.call_with_project(
                conn,
                args,
                unquote(action),
                unquote(category),
                &execute/3
              )
            end
          end

        nil ->
          quote do
            @impl EMCP.Tool
            def call(conn, args) do
              Tuist.MCP.Tool.respond(execute(conn, args))
            end
          end
      end

    quote do
      @behaviour EMCP.Tool

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_schema Keyword.fetch!(unquote(opts), :schema)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: @mcp_tool_schema

      unquote(call_impl)

      defoverridable call: 2
    end
  end

  # --- Call dispatchers ---

  def respond({:ok, data}), do: json_response(data)
  def respond({:error, message}) when is_binary(message), do: EMCP.Tool.error(message)
  def respond({:error, other}), do: EMCP.Tool.error(inspect(other))

  def call_with_project(conn, args, action, category, execute_fn) do
    case resolve_and_authorize_project(args, conn.assigns, action, category) do
      {:ok, project} -> respond(execute_fn.(conn, args, project))
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  # --- Authorization ---

  def load_and_authorize(result, assigns, action, category, not_found_message) do
    with {:ok, resource} <- load_resource(result, not_found_message),
         {:ok, project} <- authorize_project_by_id(assigns, resource.project_id, action, category) do
      {:ok, resource, project}
    end
  end

  def resolve_and_authorize_project(
        %{"account_handle" => account_handle, "project_handle" => project_handle},
        assigns,
        action,
        category
      )
      when is_binary(account_handle) and is_binary(project_handle) do
    with {:ok, project} <- load_project_by_handle(account_handle, project_handle),
         :ok <-
           authorize_project(
             assigns,
             project,
             action,
             category,
             "You do not have access to project: #{account_handle}/#{project_handle}"
           ) do
      {:ok, project}
    end
  end

  def resolve_and_authorize_project(_arguments, _assigns, _action, _category) do
    {:error, "Provide account_handle and project_handle."}
  end

  def authenticated_subject(assigns) when is_map(assigns) do
    Authorization.authenticated_subject(assigns)
  end

  # --- Response helpers ---

  def json_response(data) do
    EMCP.Tool.response([%{"type" => "text", "text" => Jason.encode!(data)}])
  end

  @max_page_size 100
  @default_page_size 20

  def page(arguments) do
    case Map.get(arguments, "page") do
      value when is_integer(value) and value > 0 -> value
      _ -> 1
    end
  end

  def page_size(arguments) do
    case Map.get(arguments, "page_size") do
      value when is_integer(value) and value > 0 -> min(value, @max_page_size)
      _ -> @default_page_size
    end
  end

  def pagination_metadata(meta) do
    %{
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      total_count: meta.total_count,
      total_pages: meta.total_pages,
      current_page: meta.current_page,
      page_size: meta.page_size
    }
  end

  # --- Internal helpers ---

  defp load_resource({:ok, resource}, _message), do: {:ok, resource}
  defp load_resource({:error, :not_found}, message), do: {:error, message}
  defp load_resource(_result, message), do: {:error, message}

  defp authorize_project_by_id(assigns, project_id, action, category) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        {:error, "Project not found."}

      project ->
        case authorize_project(assigns, project, action, category) do
          :ok -> {:ok, project}
          error -> error
        end
    end
  end

  defp load_project_by_handle(account_handle, project_handle) do
    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      nil -> {:error, "Project not found: #{account_handle}/#{project_handle}"}
      project -> {:ok, project}
    end
  end

  defp authorize_project(assigns, project, action, category, message \\ "You do not have access to this resource.") do
    if Authorization.authorize(authenticated_subject(assigns), action, project, category) do
      :ok
    else
      {:error, message}
    end
  end
end
