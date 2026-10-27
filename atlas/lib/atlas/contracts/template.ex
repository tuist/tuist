defmodule Atlas.Contracts.Template do
  @moduledoc """
  A single contract `.docx` template shipped with Atlas under
  `priv/contracts/templates/<template_set>/`.

  `kind` is derived from the filename so callers can pick a specific
  template (MSA, annexes, order forms) without parsing file names.
  """

  defstruct [:template_set, :filename, :kind, :title, :byte_size]
end
