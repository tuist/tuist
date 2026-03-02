defmodule TuistWeb.Docs.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  embed_templates "layouts/*"
end
