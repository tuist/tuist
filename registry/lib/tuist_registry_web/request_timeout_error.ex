defmodule TuistRegistryWeb.RequestTimeoutError do
  @moduledoc false

  defexception [:message, plug_status: 408]
end
