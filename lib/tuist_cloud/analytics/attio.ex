defmodule TuistCloud.Analytics.Attio do
  @moduledoc """
  A gen server that sends analytics events to Attio.
  The gen server uses ETS to store the events and sends them in batches every 10 seconds.
  """
  use GenServer, shutdown: 2_000

  require Logger

  @default_publish_interval 10_000
  @handler_id "analytics-attio"

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(_opts) do
    name = "Attio"
    table_id = create_table(String.to_atom("#{name}.Ets"))

    Process.flag(:trap_exit, true)
    attach(table_id)
    Logger.info("#{name} Started")

    {:ok, {name, table_id}, @default_publish_interval}
  end

  @impl GenServer
  def terminate(reason, {name, table_id} = state) do
    Logger.warning("[#{name}] Stopped with reason #{inspect(reason)}")
    detach()

    Logger.info("[#{name}] Flushing final events to Attio")
    events = :ets.select(table_id, [{{:"$1", :"$2"}, [], [:"$2"]}])

    if length(events) > 0 do
      events |> Enum.each(fn event -> process_event(event, state) end)
    end

    :ets.delete(table_id)
  end

  def attach(table_id) do
    :telemetry.attach_many(
      @handler_id,
      [
        [:analytics, :organization, :create],
        [:analytics, :user, :create]
      ],
      &__MODULE__.handle_event/4,
      %{table_id: table_id}
    )
  end

  def detach() do
    :telemetry.detach(@handler_id)
  end

  @impl GenServer
  def handle_info(:timeout, {name, table_id} = state) do
    Logger.debug("[#{name}] Flushing events to Attio")
    now = DateTime.to_unix(DateTime.utc_now(), :millisecond)

    events = :ets.select(table_id, [{{:"$1", :"$2"}, [{:<, :"$1", now}], [:"$2"]}])

    if length(events) > 0 do
      events |> Enum.each(fn event -> process_event(event, state) end)
      :ets.select_delete(table_id, [{{:"$1", :"$2"}, [{:<, :"$1", now}], [true]}])
    end

    {:noreply, state, @default_publish_interval}
  end

  def handle_event([:analytics | event_id], measurement, _metadata, config) do
    table_id = config[:table_id]
    date = DateTime.utc_now()

    :ets.insert(
      table_id,
      {DateTime.to_unix(date, :millisecond), Map.merge(%{event_id: event_id}, measurement)}
    )

    :ok
  end

  def process_event(
        %{event_id: [:organization, :create], name: organization_name, email: email},
        {name, _table_id}
      ) do
    company_domain = "#{organization_name}.cloud.tuist.io"

    {:ok, %{body: %{"data" => %{"id" => company_id}}}} =
      send_request("/v2/objects/companies/records?matching_attribute=domains", %{
        data: %{
          values: %{
            name: [%{value: organization_name}],
            domains: [%{domain: company_domain}]
          }
        }
      })

    company =
      if company_id != nil do
        [
          %{
            ~c"target_object" => company_id["object_id"],
            ~c"target_record_id" => company_id["record_id"]
          }
        ]
      else
        []
      end

    {:ok, _} =
      send_request("/v2/objects/people/records?matching_attribute=email_addresses", %{
        data: %{
          values: %{
            email_addresses: [%{email_address: email}],
            company: company
          }
        }
      })

    Logger.debug(
      "[#{name}] Ensured organization #{organization_name} and owner #{email} exist in Attio"
    )
  end

  def process_event(
        %{event_id: [:user, :create], email: email},
        {name, _table_id}
      ) do
    {:ok, _} =
      send_request("/v2/objects/people/records?matching_attribute=email_addresses", %{
        data: %{
          values: %{
            email_addresses: [%{email_address: email}]
          }
        }
      })

    Logger.debug("[#{name}] Ensured user #{email} exists in Attio")
  end

  defp send_request(path, body) do
    base_request()
    |> Req.put(
      url: path,
      json: body,
      headers: [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{TuistCloud.Environment.attio_api_key()}"}
      ]
    )
    |> transform_response()
  end

  defp transform_response({:ok, %{status: status} = response}) when status >= 400 do
    {:error, response}
  end

  defp transform_response(response), do: response

  defp create_table(name) do
    :ets.new(name, [:named_table, :duplicate_bag, :public, {:write_concurrency, true}])
  end

  defp base_request do
    Req.new(base_url: "https://api.attio.com")
  end
end
