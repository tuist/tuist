defmodule TuistWeb.RateLimit.PersistentTokenBucket do
  @moduledoc false

  use Hammer, backend: Hammer.Redis, timeout: 500, algorithm: :token_bucket
end
