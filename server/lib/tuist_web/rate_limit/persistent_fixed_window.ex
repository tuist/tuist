defmodule TuistWeb.RateLimit.PersistentFixedWindow do
  @moduledoc false

  use Hammer, backend: Hammer.Redis, timeout: 500, algorithm: :fix_window
end
