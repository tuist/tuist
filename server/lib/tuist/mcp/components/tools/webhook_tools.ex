defmodule Tuist.MCP.Components.Tools.WebhookTools do
  @moduledoc false

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  def authorize_account(arguments, assigns),
    do: MCPTool.resolve_and_authorize_account(arguments, assigns, :update, :account)

  def uuid_from_resource_id(value, resource_name) do
    case value |> MCPTool.resource_id() |> Ecto.UUID.cast() do
      {:ok, id} -> {:ok, id}
      :error -> {:error, "#{resource_name} identifier must be a UUID."}
    end
  end

  def endpoint_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "signing_secret_last_four" => %{"type" => ["string", "null"]},
        "event_types" => %{"type" => "array", "items" => %{"type" => "string"}},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => ["id", "name", "url", "signing_secret_last_four", "event_types", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end

  def delivery_attempt_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "webhook_endpoint_id" => %{"type" => "string"},
        "event_id" => %{"type" => "string"},
        "event_type" => %{"type" => "string"},
        "attempt" => %{"type" => "integer"},
        "status" => %{"type" => "string", "enum" => ["delivered", "failed"]},
        "request_body" => %{"type" => "string"},
        "request_headers" => %{"type" => "string"},
        "response_status" => %{"type" => "integer"},
        "response_headers" => %{"type" => "string"},
        "response_body" => %{"type" => "string"},
        "error" => %{"type" => "string"},
        "duration_ms" => %{"type" => "integer"},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "webhook_endpoint_id",
        "event_id",
        "event_type",
        "attempt",
        "status",
        "request_body",
        "request_headers",
        "response_status",
        "response_headers",
        "response_body",
        "error",
        "duration_ms",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end

  def cursor_pagination_schema do
    %{
      "type" => "object",
      "properties" => %{
        "has_next_page" => %{"type" => "boolean"},
        "has_previous_page" => %{"type" => "boolean"},
        "current_page" => %{"type" => ["integer", "null"]},
        "page_size" => %{"type" => "integer"},
        "total_count" => %{"type" => ["integer", "null"]},
        "total_pages" => %{"type" => ["integer", "null"]},
        "start_cursor" => %{"type" => ["string", "null"]},
        "end_cursor" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "has_next_page",
        "has_previous_page",
        "current_page",
        "page_size",
        "total_count",
        "total_pages",
        "start_cursor",
        "end_cursor"
      ],
      "additionalProperties" => false
    }
  end

  def serialize_endpoint(endpoint) do
    %{
      id: endpoint.id,
      name: endpoint.name,
      url: endpoint.url,
      signing_secret_last_four: endpoint.signing_secret_last_four,
      event_types: endpoint.event_types,
      inserted_at: Formatter.iso8601(endpoint.inserted_at),
      updated_at: Formatter.iso8601(endpoint.updated_at)
    }
  end

  def serialize_delivery_attempt(attempt) do
    %{
      id: attempt.id,
      webhook_endpoint_id: attempt.webhook_endpoint_id,
      event_id: attempt.event_id,
      event_type: attempt.event_type,
      attempt: attempt.attempt,
      status: attempt.status,
      request_body: attempt.request_body,
      request_headers: attempt.request_headers,
      response_status: attempt.response_status,
      response_headers: attempt.response_headers,
      response_body: attempt.response_body,
      error: attempt.error,
      duration_ms: attempt.duration_ms,
      inserted_at: Formatter.iso8601(attempt.inserted_at)
    }
  end

  def delivery_options(arguments) do
    with :ok <- validate_cursors(arguments),
         {:ok, start_datetime} <- parse_datetime(arguments, "start_datetime"),
         {:ok, end_datetime} <- parse_datetime(arguments, "end_datetime") do
      options =
        Enum.reject(
          [
            page_size: MCPTool.page_size(arguments),
            after: blank_to_nil(Map.get(arguments, "after")),
            before: blank_to_nil(Map.get(arguments, "before")),
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            status: status(Map.get(arguments, "status")),
            event_type: blank_to_nil(Map.get(arguments, "event_type")),
            event_id_search: blank_to_nil(Map.get(arguments, "event_id_search"))
          ],
          fn {_key, value} -> is_nil(value) end
        )

      {:ok, options}
    end
  end

  def pagination_metadata(metadata) do
    %{
      has_next_page: metadata.has_next_page?,
      has_previous_page: metadata.has_previous_page?,
      current_page: metadata.current_page,
      page_size: metadata.page_size,
      total_count: metadata.total_count,
      total_pages: metadata.total_pages,
      start_cursor: metadata.start_cursor,
      end_cursor: metadata.end_cursor
    }
  end

  defp validate_cursors(%{"after" => after_cursor, "before" => before_cursor})
       when is_binary(after_cursor) and after_cursor != "" and is_binary(before_cursor) and before_cursor != "",
       do: {:error, "Use only one of after or before."}

  defp validate_cursors(_arguments), do: :ok

  defp parse_datetime(arguments, key) do
    case blank_to_nil(Map.get(arguments, key)) do
      nil ->
        {:ok, nil}

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          _ -> {:error, "#{key} must be an ISO 8601 datetime."}
        end
    end
  end

  defp status("delivered"), do: :delivered
  defp status("failed"), do: :failed
  defp status(_value), do: nil

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end

defmodule Tuist.MCP.Components.Tools.ListWebhookEndpoints do
  @moduledoc """
  List webhook endpoints for an account.
  """

  use Tuist.MCP.Tool,
    name: "list_webhook_endpoints",
    title: "List Webhook Endpoints",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{"account_handle" => %{"type" => "string", "description" => "The account handle."}},
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "endpoints" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.WebhookTools.endpoint_schema()}
      },
      "required" => ["endpoints"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.WebhookTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Webhooks

  @impl EMCP.Tool
  def description, do: "List webhook endpoints for an account."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- WebhookTools.authorize_account(arguments, conn.assigns) do
      endpoints = account.id |> Webhooks.list_endpoints() |> Enum.map(&WebhookTools.serialize_endpoint/1)
      MCPTool.json_response(%{endpoints: endpoints}, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetWebhookEndpoint do
  @moduledoc """
  Get a webhook endpoint for an account.
  """

  use Tuist.MCP.Tool,
    name: "get_webhook_endpoint",
    title: "Get Webhook Endpoint",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "webhook_endpoint_id" => %{
          "type" => "string",
          "description" => "The webhook endpoint identifier or dashboard URL."
        }
      },
      "required" => ["account_handle", "webhook_endpoint_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.WebhookTools.endpoint_schema()

  alias Tuist.MCP.Components.Tools.WebhookTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Webhooks

  @impl EMCP.Tool
  def description, do: "Get a webhook endpoint for an account."

  @impl EMCP.Tool
  def call(conn, %{"webhook_endpoint_id" => endpoint_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, endpoint_id} <- WebhookTools.uuid_from_resource_id(endpoint_id, "Webhook endpoint"),
         {:ok, account} <- WebhookTools.authorize_account(arguments, conn.assigns),
         {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, account.id) do
      MCPTool.json_response(WebhookTools.serialize_endpoint(endpoint), __MODULE__)
    else
      {:error, :not_found} -> EMCP.Tool.error("Webhook endpoint not found: #{endpoint_id}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListWebhookDeliveryAttempts do
  @moduledoc """
  List webhook delivery attempts for an endpoint.
  """

  use Tuist.MCP.Tool,
    name: "list_webhook_delivery_attempts",
    title: "List Webhook Delivery Attempts",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "webhook_endpoint_id" => %{
          "type" => "string",
          "description" => "The webhook endpoint identifier or dashboard URL."
        },
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, maximum: 100)."},
        "after" => %{"type" => "string", "description" => "Cursor for the next page."},
        "before" => %{"type" => "string", "description" => "Cursor for the previous page."},
        "start_datetime" => %{"type" => "string", "description" => "Inclusive ISO 8601 start time."},
        "end_datetime" => %{"type" => "string", "description" => "Inclusive ISO 8601 end time."},
        "status" => %{"type" => "string", "enum" => ["delivered", "failed"]},
        "event_type" => %{"type" => "string"},
        "event_id_search" => %{"type" => "string"}
      },
      "required" => ["account_handle", "webhook_endpoint_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "delivery_attempts" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.WebhookTools.delivery_attempt_schema()
        },
        "pagination_metadata" => Tuist.MCP.Components.Tools.WebhookTools.cursor_pagination_schema()
      },
      "required" => ["delivery_attempts", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.WebhookTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Webhooks

  @impl EMCP.Tool
  def description, do: "List webhook delivery attempts for an endpoint."

  @impl EMCP.Tool
  def call(conn, %{"webhook_endpoint_id" => endpoint_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, endpoint_id} <- WebhookTools.uuid_from_resource_id(endpoint_id, "Webhook endpoint"),
         {:ok, account} <- WebhookTools.authorize_account(arguments, conn.assigns),
         {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, account.id),
         {:ok, options} <- WebhookTools.delivery_options(arguments) do
      {attempts, metadata} = Webhooks.list_deliveries(endpoint.id, options)

      MCPTool.json_response(
        %{
          delivery_attempts: Enum.map(attempts, &WebhookTools.serialize_delivery_attempt/1),
          pagination_metadata: WebhookTools.pagination_metadata(metadata)
        },
        __MODULE__
      )
    else
      {:error, :not_found} -> EMCP.Tool.error("Webhook endpoint not found: #{endpoint_id}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetWebhookDeliveryAttempt do
  @moduledoc """
  Get a webhook delivery attempt for an endpoint.
  """

  use Tuist.MCP.Tool,
    name: "get_webhook_delivery_attempt",
    title: "Get Webhook Delivery Attempt",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "webhook_endpoint_id" => %{
          "type" => "string",
          "description" => "The webhook endpoint identifier or dashboard URL."
        },
        "delivery_attempt_id" => %{
          "type" => "string",
          "description" => "The delivery attempt identifier or dashboard URL."
        }
      },
      "required" => ["account_handle", "webhook_endpoint_id", "delivery_attempt_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.WebhookTools.delivery_attempt_schema()

  alias Tuist.MCP.Components.Tools.WebhookTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Webhooks

  @impl EMCP.Tool
  def description, do: "Get a webhook delivery attempt for an endpoint."

  @impl EMCP.Tool
  def call(conn, %{"webhook_endpoint_id" => endpoint_id, "delivery_attempt_id" => attempt_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, endpoint_id} <- WebhookTools.uuid_from_resource_id(endpoint_id, "Webhook endpoint"),
         {:ok, attempt_id} <- WebhookTools.uuid_from_resource_id(attempt_id, "Webhook delivery attempt"),
         {:ok, account} <- WebhookTools.authorize_account(arguments, conn.assigns),
         {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, account.id),
         {:ok, attempt} <- Webhooks.get_delivery_attempt(endpoint.id, attempt_id) do
      MCPTool.json_response(WebhookTools.serialize_delivery_attempt(attempt), __MODULE__)
    else
      {:error, :not_found} -> EMCP.Tool.error("Webhook delivery attempt not found: #{attempt_id}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end
