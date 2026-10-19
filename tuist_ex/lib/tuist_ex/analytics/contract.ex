defmodule TuistEx.Analytics.Contract do
  @moduledoc false

  # Wire contract version the plugin was built against. Server accepts
  # unknown values; older clients may omit it entirely. Deploy server support for
  # up_to_date local hits before releasing this contract to clients.
  @version "0.2"

  def version, do: @version
end
