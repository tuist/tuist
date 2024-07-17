defmodule TuistWeb.Layouts do
  use TuistWeb, :html
  import TuistWeb.AppLayoutComponents

  embed_templates "layouts/*"
end
