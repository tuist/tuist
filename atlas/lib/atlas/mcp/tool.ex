defmodule Atlas.MCP.Tool do
  @moduledoc """
  Macro and helpers for defining EMCP tools in Atlas. Tools declare a
  `name`, an `input_schema`, an `output_schema`, and implement `execute/2`
  receiving the Plug.Conn (for `current_user`) and parsed arguments. The macro
  wraps `execute/2` so it returns an EMCP response tuple carrying both the text
  serialization and the `structuredContent` described by the output schema.
  """

  use AtlasWeb, :verified_routes

  alias Atlas.Documents.Document
  alias Atlas.Environment
  alias Atlas.Users
  alias Atlas.Users.User
  alias AtlasWeb.DocumentLinks

  require Logger

  defmacro __using__(opts) do
    quote do
      @behaviour EMCP.Tool

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_schema Keyword.fetch!(unquote(opts), :schema)
      @mcp_tool_output_schema Atlas.MCP.Tool.validate_output_schema!(
                                @mcp_tool_name,
                                Keyword.fetch!(unquote(opts), :output_schema)
                              )
      @mcp_tool_resolved_output_schema ExJsonSchema.Schema.resolve(@mcp_tool_output_schema)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: @mcp_tool_schema

      def output_schema, do: @mcp_tool_output_schema

      def resolved_output_schema, do: @mcp_tool_resolved_output_schema

      @impl EMCP.Tool
      def call(conn, args) when is_map(args), do: Atlas.MCP.Tool.respond(execute(conn, args), __MODULE__)

      def call(_conn, _args), do: Atlas.MCP.Tool.respond({:error, "arguments must be an object."}, __MODULE__)

      defoverridable call: 2
    end
  end

  def respond({:ok, data}, module), do: json_response(data, module)
  def respond({:error, message}, _module) when is_binary(message), do: EMCP.Tool.error(message)
  def respond({:error, other}, _module), do: EMCP.Tool.error(inspect(other))

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
    raise ArgumentError, "MCP tool #{module.name()} must return a map as structured content, got: #{inspect(data)}"
  end

  @doc """
  The `tools/list` entry for a tool, extended with the output schema clients use
  to navigate `structuredContent` without parsing the text serialization.
  """
  def descriptor(module) do
    module
    |> EMCP.Tool.to_map()
    |> Map.put("outputSchema", module.output_schema())
  end

  @doc """
  Widens a schema fragment so it also accepts `null`, for serializer output that is
  either the described shape or nothing at all.
  """
  def nullable(%{"type" => type} = schema) when is_binary(type), do: %{schema | "type" => [type, "null"]}

  @doc """
  Asserts at compile time that a tool declares an object output schema. A tool that
  violates this would otherwise only fail once a client requested `tools/list`,
  taking down tool discovery for every other tool along with it.
  """
  def validate_output_schema!(name, schema) do
    if not is_map(schema) or (schema["type"] not in ["object", :object] and schema[:type] not in ["object", :object]) do
      raise ArgumentError, "MCP tool #{name} must provide an object output schema"
    end

    schema
  end

  def current_user(%{assigns: assigns}), do: assigns[:current_user]
  def current_user(_conn), do: nil

  def authorize_authenticated(conn, label \\ "These tools") do
    case current_user(conn) do
      %User{} -> :ok
      _user -> {:error, "#{label} require an authenticated user."}
    end
  end

  def authorize_executive(conn, label \\ "Finance tools") do
    case current_user(conn) do
      %User{} = user ->
        if Users.executive?(user), do: :ok, else: {:error, "#{label} are only available to executives."}

      _user ->
        {:error, "#{label} require an authenticated executive user."}
    end
  end

  @max_page_size 100
  @default_page_size 20

  def page_size(args) do
    case Map.get(args, "page_size") do
      v when is_integer(v) and v > 0 -> min(v, @max_page_size)
      _ -> @default_page_size
    end
  end

  @doc """
  Stable, shareable link for opening a document. The endpoint authorizes the
  executive and redirects to a fresh signed object link when available.
  """
  def document_url(%Document{} = document) do
    DocumentLinks.download_url(document)
  end

  def document_url(document_id) when is_binary(document_id) do
    url(~p"/documents/#{document_id}/download")
  end

  def account_url(account_id) when is_binary(account_id) do
    url(~p"/commercial/sales/accounts/#{account_id}")
  end

  def note_url(note_id) when is_binary(note_id) do
    url(~p"/library/notes/#{note_id}")
  end

  def hardware_url do
    url(~p"/operations/hardware")
  end

  def asset_url(asset_id) when is_binary(asset_id) do
    url(~p"/operations/hardware/#{asset_id}")
  end

  def financings_url do
    url(~p"/operations/hardware/financings")
  end

  def financing_url(financing_id) when is_binary(financing_id) do
    url(~p"/operations/hardware/financings/#{financing_id}")
  end

  def data_centers_url do
    url(~p"/operations/hardware/data-centers")
  end

  def data_center_url(data_center_id) when is_binary(data_center_id) do
    url(~p"/operations/hardware/data-centers/#{data_center_id}")
  end

  def insurance_policies_url do
    url(~p"/operations/hardware/insurance")
  end

  def insurance_policy_url(policy_id) when is_binary(policy_id) do
    url(~p"/operations/hardware/insurance/#{policy_id}")
  end

  def licenses_url do
    url(~p"/commercial/sales/licenses")
  end

  def iso8601(nil), do: nil
  def iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def iso8601(%NaiveDateTime{} = dt) do
    dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  end

  def iso8601(other), do: to_string(other)

  def format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  # Schema drift is a bug in the tool's declared output schema, not in the caller's
  # request. Raise where a developer or CI sees it immediately, but never turn a
  # successful query into a 500 for a client that could have used the response.
  # Logged at :error so the Sentry handler, which only captures :error, reports it.
  defp validate_structured_content(module, structured_content) do
    case ExJsonSchema.Validator.validate(module.resolved_output_schema(), structured_content) do
      :ok ->
        :ok

      {:error, errors} ->
        message = "MCP tool #{module.name()} returned invalid structured content: #{inspect(errors)}"

        if Environment.dev?() or Environment.test?() do
          raise message
        else
          Logger.error(message)
          :ok
        end
    end
  end
end
