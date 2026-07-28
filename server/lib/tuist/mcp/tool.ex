defmodule Tuist.MCP.Tool do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.Projects

  require Logger

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
                &execute/3,
                __MODULE__
              )
            end
          end

        nil ->
          quote do
            @impl EMCP.Tool
            def call(conn, args) do
              Tuist.MCP.Tool.respond(execute(conn, args), __MODULE__)
            end
          end
      end

    quote do
      @behaviour EMCP.Tool

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_schema Keyword.fetch!(unquote(opts), :schema)
      @mcp_tool_output_schema Tuist.MCP.Tool.validate_output_schema!(
                                @mcp_tool_name,
                                Keyword.fetch!(unquote(opts), :output_schema)
                              )
      @mcp_tool_resolved_output_schema ExJsonSchema.Schema.resolve(@mcp_tool_output_schema)
      @mcp_tool_title Keyword.fetch!(unquote(opts), :title)
      @mcp_tool_read_only_hint Keyword.get(unquote(opts), :read_only_hint, true)
      @mcp_tool_open_world_hint Keyword.get(unquote(opts), :open_world_hint, false)
      @mcp_tool_destructive_hint Keyword.get(unquote(opts), :destructive_hint, false)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: @mcp_tool_schema

      def output_schema, do: @mcp_tool_output_schema

      def resolved_output_schema, do: @mcp_tool_resolved_output_schema

      @impl EMCP.Tool
      def annotations do
        %{
          title: @mcp_tool_title,
          readOnlyHint: @mcp_tool_read_only_hint,
          openWorldHint: @mcp_tool_open_world_hint,
          destructiveHint: @mcp_tool_destructive_hint
        }
      end

      unquote(call_impl)

      defoverridable call: 2
    end
  end

  # --- Call dispatchers ---

  def respond({:ok, data}, module), do: json_response(data, module)
  def respond({:error, message}, _module) when is_binary(message), do: EMCP.Tool.error(message)
  def respond({:error, other}, _module), do: EMCP.Tool.error(inspect(other))

  def call_with_project(conn, args, action, category, execute_fn, module) do
    case resolve_and_authorize_project(args, conn.assigns, action, category) do
      {:ok, project} -> respond(execute_fn.(conn, args, project), module)
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

  def json_response(data, module) when is_map(data) do
    encoded = JSON.encode!(data)
    structured_content = JSON.decode!(encoded)

    validate_structured_content(module, structured_content)

    %{
      "content" => [%{"type" => "text", "text" => encoded}],
      "structuredContent" => structured_content
    }
  end

  def json_response(data, module) do
    raise ArgumentError,
          "MCP tool #{module.name()} must return a map as structured content, got: #{inspect(data)}"
  end

  def descriptor(module) do
    module
    |> EMCP.Tool.to_map()
    |> Map.put("outputSchema", module.output_schema())
  end

  @doc """
  Asserts at compile time that a tool declares an object output schema. Tools that
  violate this would otherwise only fail once a client requested `tools/list`, taking
  down tool discovery for every other tool along with them.
  """
  def validate_output_schema!(name, schema) do
    if not is_map(schema) or (schema["type"] not in ["object", :object] and schema[:type] not in ["object", :object]) do
      raise ArgumentError, "MCP tool #{name} must provide an object output schema"
    end

    schema
  end

  @doc """
  The output schema fragment describing `pagination_metadata/1`. Shared so the schema
  and the payload it describes cannot drift apart.
  """
  def pagination_metadata_schema do
    %{
      "type" => "object",
      "properties" => %{
        "has_next_page" => %{"type" => "boolean"},
        "has_previous_page" => %{"type" => "boolean"},
        "total_count" => %{"type" => "integer"},
        "total_pages" => %{"type" => "integer"},
        "current_page" => %{"type" => "integer"},
        "page_size" => %{"type" => "integer"}
      },
      "required" => [
        "has_next_page",
        "has_previous_page",
        "total_count",
        "total_pages",
        "current_page",
        "page_size"
      ],
      "additionalProperties" => false
    }
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

  # Schema drift is a bug in the tool's declared output schema, not in the caller's
  # request. Raise where a test or a developer will see it, but never turn a
  # successful query into a 500 for a client that could have used the response.
  # Logged at :error so the Sentry handler, which only captures :error, reports it.
  defp validate_structured_content(module, structured_content) do
    case ExJsonSchema.Validator.validate(module.resolved_output_schema(), structured_content) do
      :ok ->
        :ok

      {:error, errors} ->
        message = "MCP tool #{module.name()} returned invalid structured content: #{inspect(errors)}"

        if Tuist.Environment.dev?() or Tuist.Environment.test?() do
          raise message
        else
          Logger.error(message)
          :ok
        end
    end
  end

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
