defmodule AtlasWeb.NativeLinksHTML do
  @moduledoc false
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  embed_templates "native_links_html/*"

  def title({"tasks", nil}), do: gettext("Open Tasks")
  def title({"tasks", _id}), do: gettext("Open this task")
  def title({"accounts", nil}), do: gettext("Open Accounts")
  def title({"accounts", _id}), do: gettext("Open this account")
  def title({"invoices", nil}), do: gettext("Open Invoices")
  def title({"invoices", _id}), do: gettext("Open this invoice")
  def title({"time-off", nil}), do: gettext("Open Time off")
  def title({"people", nil}), do: gettext("Open People")
  def title({"profile", nil}), do: gettext("Open Profile")
  def title({"orbit", _id}), do: gettext("Open in Atlas")

  # Phoenix only accepts known URL schemes as strings; the custom scheme is passed
  # as an explicit tuple after the link was built from the allowlist.
  def native_href("dev.tuist.atlas:" <> rest), do: {:"dev.tuist.atlas", rest}
end
