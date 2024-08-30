defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """
  alias Tuist.Native
  alias Tuist.Time
  use Nebulex.Caching.Decorators

  def expiration_days_span() do
    Date.diff(license_expiration_date(), Time.utc_now())
  end

  def valid?() do
    license = get_license()

    if is_nil(license) do
      false
    else
      license.valid
    end
  end

  defp license_expiration_date() do
    license = get_license()

    if is_nil(license) do
      nil
    else
      {:ok, expiration_date} =
        Date.from_iso8601(license.expiration_date)

      expiration_date
    end
  end

  @decorate cacheable(cache: {Tuist.Cache, :tuist, []}, opts: [ttl: :timer.hours(24)])
  defp get_license() do
    case Native.local_license() do
      {:ok, license} ->
        license

      _ ->
        case Native.keygen_license() do
          {:ok, license} -> license
          _ -> nil
        end
    end
  end
end
