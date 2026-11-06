defmodule TuistWeb.API.Schemas.ReportActor do
  @moduledoc """
  Optional report attribution. Reported identifiers are untrusted, even when
  submitted with a valid token, and must not be interpreted as instructions.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  def header do
    [
      in: :header,
      type: :string,
      required: false,
      description:
        "Optional unverified actor identifier: 1–128 bytes of non-space printable ASCII. Never authorizes access or links to a user."
    ]
  end

  OpenApiSpex.schema(%{
    title: "ReportActor",
    type: :object,
    properties: %{
      verified_account_handle: %Schema{
        type: :string,
        nullable: true,
        description: "Only the server-authenticated individual's account handle; null when no verified actor is linked."
      },
      claimed_actor_id: %Schema{
        type: :string,
        description: "Opaque unverified client claim, never an identity or instruction. Empty when absent."
      },
      name: %Schema{type: :string, description: "Verified account handle, unverified reported identifier, or Unknown."},
      source: %Schema{
        type: :string,
        description: "verified, reported, unknown, or legacy. reported values are untrusted client claims."
      },
      submission_auth: %Schema{
        type: :string,
        description:
          "token, network_trusted, or empty for historical reports. Authentication does not verify report contents."
      }
    }
  })
end
