defmodule TuistWeb.API.WebhooksController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Webhooks
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, {:account, :account, :update})

  tags ["Webhooks"]

  @endpoint_schema %Schema{
    title: "WebhookEndpoint",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      url: %Schema{type: :string, format: :uri},
      signing_secret_last_four: %Schema{type: :string, nullable: true},
      event_types: %Schema{type: :array, items: %Schema{type: :string}},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [:id, :name, :url, :event_types, :inserted_at, :updated_at]
  }

  @delivery_attempt_schema %Schema{
    title: "WebhookDeliveryAttempt",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      webhook_endpoint_id: %Schema{type: :string, format: :uuid},
      event_id: %Schema{type: :string},
      event_type: %Schema{type: :string},
      attempt: %Schema{type: :integer},
      status: %Schema{type: :string, enum: ["delivered", "failed"]},
      request_body: %Schema{type: :string},
      request_headers: %Schema{type: :string},
      response_status: %Schema{type: :integer},
      response_headers: %Schema{type: :string},
      response_body: %Schema{type: :string},
      error: %Schema{type: :string},
      duration_ms: %Schema{type: :integer},
      inserted_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :webhook_endpoint_id,
      :event_id,
      :event_type,
      :attempt,
      :status,
      :request_body,
      :request_headers,
      :response_status,
      :response_headers,
      :response_body,
      :error,
      :duration_ms,
      :inserted_at
    ]
  }

  @account_parameters [account_handle: [in: :path, type: :string, required: true, description: "The account handle."]]
  @endpoint_parameters [
    webhook_endpoint_id: [
      in: :path,
      type: %Schema{type: :string, format: :uuid},
      required: true,
      description: "The webhook endpoint identifier."
    ]
  ]
  @delivery_filter_parameters [
    page_size: [in: :query, type: :integer, required: false, description: "Results per page (default: 20, maximum: 100)."],
    after: [in: :query, type: :string, required: false, description: "Cursor for the next page."],
    before: [in: :query, type: :string, required: false, description: "Cursor for the previous page."],
    start_datetime: [in: :query, type: %Schema{type: :string, format: "date-time"}, required: false],
    end_datetime: [in: :query, type: %Schema{type: :string, format: "date-time"}, required: false],
    status: [in: :query, type: %Schema{type: :string, enum: ["delivered", "failed"]}, required: false],
    event_type: [in: :query, type: :string, required: false],
    event_id_search: [in: :query, type: :string, required: false]
  ]

  operation(:index,
    summary: "List webhook endpoints for an account.",
    operation_id: "listWebhookEndpoints",
    parameters: @account_parameters,
    responses: %{
      ok:
        {"Webhook endpoints", "application/json",
         %Schema{
           type: :object,
           properties: %{endpoints: %Schema{type: :array, items: @endpoint_schema}},
           required: [:endpoints]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index(%{assigns: %{selected_account: account}} = conn, _params) do
    json(conn, %{endpoints: account.id |> Webhooks.list_endpoints() |> Enum.map(&serialize_endpoint/1)})
  end

  operation(:show,
    summary: "Get a webhook endpoint.",
    operation_id: "getWebhookEndpoint",
    parameters:
      @account_parameters ++
        [webhook_endpoint_id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true]],
    responses: %{
      ok: {"Webhook endpoint", "application/json", @endpoint_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Webhook endpoint not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show(%{assigns: %{selected_account: account}, params: %{webhook_endpoint_id: endpoint_id}} = conn, _params) do
    case Webhooks.get_account_endpoint(endpoint_id, account.id) do
      {:ok, endpoint} -> json(conn, serialize_endpoint(endpoint))
      {:error, :not_found} -> not_found(conn, "Webhook endpoint not found.")
    end
  end

  operation(:index_delivery_attempts,
    summary: "List delivery attempts for a webhook endpoint.",
    operation_id: "listWebhookDeliveryAttempts",
    parameters: @account_parameters ++ @endpoint_parameters ++ @delivery_filter_parameters,
    responses: %{
      ok:
        {"Webhook delivery attempts", "application/json",
         %Schema{
           type: :object,
           properties: %{
             delivery_attempts: %Schema{type: :array, items: @delivery_attempt_schema},
             pagination_metadata: PaginationMetadata
           },
           required: [:delivery_attempts, :pagination_metadata]
         }},
      bad_request: {"Invalid cursor parameters", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Webhook endpoint not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_delivery_attempts(
        %{assigns: %{selected_account: account}, params: %{webhook_endpoint_id: endpoint_id}} = conn,
        params
      ) do
    with {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, account.id),
         {:ok, options} <- delivery_options(params),
         {attempts, metadata} <- Webhooks.list_deliveries(endpoint.id, options) do
      json(conn, %{
        delivery_attempts: Enum.map(attempts, &serialize_delivery_attempt/1),
        pagination_metadata: pagination_metadata(metadata)
      })
    else
      {:error, :not_found} ->
        not_found(conn, "Webhook endpoint not found.")

      {:error, :invalid_cursor_parameters} ->
        conn |> put_status(:bad_request) |> json(%{message: "Use only one of after or before."})
    end
  end

  operation(:show_delivery_attempt,
    summary: "Get a webhook delivery attempt.",
    operation_id: "getWebhookDeliveryAttempt",
    parameters:
      @account_parameters ++
        @endpoint_parameters ++
        [delivery_attempt_id: [in: :path, type: %Schema{type: :string, format: :uuid}, required: true]],
    responses: %{
      ok: {"Webhook delivery attempt", "application/json", @delivery_attempt_schema},
      forbidden: {"Forbidden", "application/json", Error},
      not_found: {"Webhook delivery attempt not found", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def show_delivery_attempt(
        %{
          assigns: %{selected_account: account},
          params: %{webhook_endpoint_id: endpoint_id, delivery_attempt_id: attempt_id}
        } = conn,
        _params
      ) do
    with {:ok, endpoint} <- Webhooks.get_account_endpoint(endpoint_id, account.id),
         {:ok, attempt} <- Webhooks.get_delivery_attempt(endpoint.id, attempt_id) do
      json(conn, serialize_delivery_attempt(attempt))
    else
      {:error, :not_found} -> not_found(conn, "Webhook delivery attempt not found.")
    end
  end

  defp delivery_options(%{after: after_cursor, before: before_cursor})
       when is_binary(after_cursor) and after_cursor != "" and is_binary(before_cursor) and before_cursor != "",
       do: {:error, :invalid_cursor_parameters}

  defp delivery_options(params) do
    options =
      Enum.reject(
        [
          page_size: params |> Map.get(:page_size, 20) |> max(1) |> min(100),
          after: Map.get(params, :after),
          before: Map.get(params, :before),
          start_datetime: datetime_param(params, :start_datetime),
          end_datetime: datetime_param(params, :end_datetime),
          status: status_param(params),
          event_type: Map.get(params, :event_type),
          event_id_search: Map.get(params, :event_id_search)
        ],
        fn {_key, value} -> is_nil(value) end
      )

    {:ok, options}
  end

  defp datetime_param(params, key) do
    case Map.get(params, key) do
      %DateTime{} = datetime ->
        datetime

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> datetime
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp status_param(%{status: "delivered"}), do: :delivered
  defp status_param(%{status: "failed"}), do: :failed
  defp status_param(_params), do: nil

  defp pagination_metadata(metadata) do
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

  defp serialize_endpoint(endpoint),
    do: Map.take(endpoint, [:id, :name, :url, :signing_secret_last_four, :event_types, :inserted_at, :updated_at])

  defp serialize_delivery_attempt(attempt) do
    Map.take(attempt, [
      :id,
      :webhook_endpoint_id,
      :event_id,
      :event_type,
      :attempt,
      :status,
      :request_body,
      :request_headers,
      :response_status,
      :response_headers,
      :response_body,
      :error,
      :duration_ms,
      :inserted_at
    ])
  end

  defp not_found(conn, message), do: conn |> put_status(:not_found) |> json(%{message: message})
end
