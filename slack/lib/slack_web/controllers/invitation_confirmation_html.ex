defmodule SlackWeb.InvitationConfirmationHTML do
  @moduledoc """
  Templates for the invitation confirmation flow.
  """
  use SlackWeb, :html
  use Noora

  embed_templates "invitation_confirmation_html/*"
end
