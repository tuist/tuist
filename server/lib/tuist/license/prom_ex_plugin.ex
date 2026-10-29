defmodule Tuist.License.PromExPlugin do
  @moduledoc """
  Publishes the cached license status and expiration time.
  """

  use PromEx.Plugin

  alias Tuist.Environment
  alias Tuist.License
  alias Tuist.Telemetry

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(minute: 10))

    [
      Polling.build(
        :tuist_license_status_metrics,
        poll_rate,
        {__MODULE__, :execute_license_status_telemetry_event, []},
        [
          last_value(
            [:tuist, :license, :expiration, :timestamp, :seconds],
            event_name: Telemetry.event_name_license_status(),
            description: "Unix timestamp at which the configured Tuist license expires.",
            measurement: :expiration_timestamp_seconds
          ),
          last_value(
            [:tuist, :license, :valid],
            event_name: Telemetry.event_name_license_status(),
            description: "Whether the configured Tuist license is currently valid.",
            measurement: :valid
          )
        ]
      )
    ]
  end

  def execute_license_status_telemetry_event do
    license =
      if Environment.license_certificate_base64() do
        License.resolve_certificate()
      else
        License.get_cached_license() || {:error, :license_not_cached}
      end

    measurements = license_status_measurements(license)

    :telemetry.execute(Telemetry.event_name_license_status(), measurements, %{})
  end

  def license_status_measurements({:ok, %License{expiration_date: %DateTime{} = expiration_date, valid: valid}}) do
    %{
      expiration_timestamp_seconds: DateTime.to_unix(expiration_date),
      valid: if(valid, do: 1, else: 0)
    }
  end

  def license_status_measurements(_result), do: %{expiration_timestamp_seconds: 0, valid: 0}
end
