defmodule Tuist.MCP.Tool do
  @moduledoc false

  alias Tuist.Accounts
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
              case Tuist.MCP.Tool.validate_input(__MODULE__, args) do
                :ok ->
                  Tuist.MCP.Tool.call_with_project(
                    conn,
                    args,
                    unquote(action),
                    unquote(category),
                    &execute/3,
                    __MODULE__
                  )

                {:error, message} ->
                  EMCP.Tool.error(message)
              end
            end
          end

        nil ->
          quote do
            @impl EMCP.Tool
            def call(conn, args) do
              case Tuist.MCP.Tool.validate_input(__MODULE__, args) do
                :ok -> Tuist.MCP.Tool.respond(execute(conn, args), __MODULE__)
                {:error, message} -> EMCP.Tool.error(message)
              end
            end
          end
      end

    quote do
      @behaviour EMCP.Tool

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_schema Keyword.fetch!(unquote(opts), :schema)
      @mcp_tool_resolved_input_schema ExJsonSchema.Schema.resolve(@mcp_tool_schema)
      @mcp_tool_output_schema Tuist.MCP.Tool.validate_output_schema!(
                                @mcp_tool_name,
                                Keyword.fetch!(unquote(opts), :output_schema)
                              )
      @mcp_tool_resolved_output_schema ExJsonSchema.Schema.resolve(@mcp_tool_output_schema)
      @mcp_tool_title Keyword.fetch!(unquote(opts), :title)
      # Required rather than defaulted. A tool author who says nothing is exactly
      # the case this cannot guess at, and guessing "read-only" hands every
      # client that trusts the annotation a write tool wearing a safe label —
      # the annotation is advisory in the protocol, but proxies and agent
      # harnesses gate on it. Failing to compile puts the decision in front of
      # the person introducing the risk, while it is still cheap to make.
      @mcp_tool_read_only_hint Keyword.fetch!(unquote(opts), :read_only_hint)
      @mcp_tool_open_world_hint Keyword.get(unquote(opts), :open_world_hint, false)
      @mcp_tool_destructive_hint Keyword.get(unquote(opts), :destructive_hint, false)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: @mcp_tool_schema

      def resolved_input_schema, do: @mcp_tool_resolved_input_schema

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

  def validate_input(module, arguments) when is_map(arguments) do
    case ExJsonSchema.Validator.validate(module.resolved_input_schema(), arguments) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the tool schema."}
    end
  end

  def validate_input(_module, _arguments), do: {:error, "Arguments do not match the tool schema."}

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

  def resolve_and_authorize_account(%{"account_handle" => account_handle}, assigns, action, category)
      when is_binary(account_handle) do
    case Accounts.get_account_by_handle(account_handle) do
      nil -> {:error, "Account not found: #{account_handle}"}
      account -> authorize_account(assigns, account, action, category)
    end
  end

  def resolve_and_authorize_account(_arguments, _assigns, _action, _category) do
    {:error, "Provide account_handle."}
  end

  def authorize_account(assigns, account, action, category) do
    if Authorization.authorize_request(assigns, action, account, category) do
      {:ok, account}
    else
      {:error, "You do not have access to account: #{account.name}"}
    end
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

  @doc """
  Normalises an id argument that a caller may have pasted as a Tuist dashboard URL.

  Takes the last non-empty path segment of anything that parses as an absolute URL,
  and passes every other value through untouched so the caller's own lookup still
  rejects it. Working on the last segment rather than per-resource routes is what
  makes one helper cover build runs, test runs, test cases, bundles, cache runs,
  generations and Gradle builds.

  The host is deliberately not checked against `Tuist.Environment.app_url/2`. A
  dashboard URL reaches a self-hosted instance under its own domain, and a
  hosted one through whatever proxy or custom domain the account browses it by,
  so a host check would reject the URLs users actually have. It buys no
  authorization either: the extracted id is loaded and authorized exactly as a
  bare id is, and a URL pointing anywhere else simply yields an id that is not
  found.

  This lives here rather than in the domain lookups because those are also
  called from API controllers and LiveViews, where a URL is not a valid id.
  """
  def resource_id(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, path: path} when is_binary(scheme) and is_binary(host) ->
        path
        |> to_string()
        |> String.split("/", trim: true)
        |> List.last()
        |> case do
          nil -> value
          segment -> segment
        end

      _ ->
        value
    end
  end

  def resource_id(value), do: value

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
    if Authorization.authorize_request(assigns, action, project, category) do
      :ok
    else
      {:error, denial_message(message, project)}
    end
  end

  # A caller refused for want of an operator grant cannot act on that without
  # knowing which account to request one for, and a tool call names a record
  # rather than an account. Naming the owner here is what lets a client turn
  # the refusal into a next step instead of a dead end.
  #
  # The shape is a contract, not prose: `Tuist.MCP.ToolTest` pins it, and
  # Atlas parses it to build a pre-filled access request. Change the wording
  # and that client stops recognising it — it fails closed, to a refusal with
  # no link, but it does fail.
  #
  # This tells a caller who cannot read the record which account owns it. They
  # are an authenticated Tuist user, and the handle is the name they would ask
  # for access to by, so the disclosure is the point rather than a leak.
  defp denial_message(message, %{account: %{name: handle}}) when is_binary(handle) do
    ~s(#{end_sentence(message)} It belongs to the account "#{handle}".)
  end

  # An unloaded association would render as a struct rather than a handle, so
  # say nothing rather than something wrong.
  defp denial_message(message, _project), do: message

  defp end_sentence(message) do
    if String.ends_with?(message, [".", "!", "?"]), do: message, else: message <> "."
  end
end
