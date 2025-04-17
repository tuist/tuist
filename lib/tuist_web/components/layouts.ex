defmodule TuistWeb.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use TuistWeb.Noora

  embed_templates "layouts/*"
end
