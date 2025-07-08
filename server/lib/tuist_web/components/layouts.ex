defmodule TuistWeb.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  embed_templates "layouts/*"
end
