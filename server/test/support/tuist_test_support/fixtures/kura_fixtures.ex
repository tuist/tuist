defmodule TuistTestSupport.Fixtures.KuraFixtures do
  @moduledoc false

  alias Tuist.Kura.Server
  alias Tuist.Repo

  @doc """
  An active instance in a public region, which is what makes the account
  resolve its URL: cache resolution reads `kura_servers` directly.
  """
  def active_server_fixture(account, opts \\ []) do
    region = Keyword.get(opts, :region, "local-controller")

    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: :active,
      url: Keyword.get(opts, :url, "https://#{account.name}-#{region}-1.kura.tuist.dev"),
      current_image_tag: Keyword.get(opts, :image_tag, "0.5.2"),
      provisioner_node_ref: "kura-#{account.id}-#{region}"
    })
  end
end
