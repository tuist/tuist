defmodule TuistOpsWeb.Layouts do
  @moduledoc """
  Root document + the ops sidebar shell, mirroring the `tuist.dev/ops`
  layout. Noora's prebuilt `noora.css` (served from `priv/static/assets`)
  carries the component styling; the shell flexbox lives in `root`.
  """
  use TuistOpsWeb, :html

  embed_templates "layouts/*"
end
