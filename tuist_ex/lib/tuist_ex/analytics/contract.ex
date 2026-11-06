defmodule TuistEx.Analytics.Contract do
  @moduledoc false

  # Wire contract version the plugin was built against. Server accepts
  # unknown values; older clients may omit it entirely. Older validators reject
  # up_to_date hits, so submission retries once without those observations.
  @version "0.2"

  def version, do: @version
end
