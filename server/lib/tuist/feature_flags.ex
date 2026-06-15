defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment

  @doc """
  Whether the Runners dashboard (and its sub-pages) should be visible
  for the given account. Defaults to enabled in any non-prod
  environment (dev / test / staging / canary) so contributors and
  internal testers see it without the flag flipped; in production it
  requires an explicit `:runners` FunWithFlags toggle for the actor.
  """
  def runners_enabled?(account) do
    not Environment.prod?() or FunWithFlags.enabled?(:runners, for: account)
  end

  @doc """
  Whether the managed Kura deployment surface (the per-account Kura
  servers and the Usage dashboard) should be visible for the given
  account. Mirrors the inline check already used in
  `account_settings_live` so the sidebar entry, the LiveView guard,
  and the settings page all answer the same question.
  """
  def kura_enabled?(account) do
    Environment.dev?() or FunWithFlags.enabled?(:kura, for: account)
  end

  @doc """
  Whether cache clients should use Kura endpoints for the given account.
  This is intentionally separate from `:kura`, which controls access to the
  managed Kura UI and provisioning surface. Kura is opt-in: accounts continue
  to use the default cache endpoints unless this flag is explicitly enabled.
  """
  def kura_cache_enabled?(account) do
    FunWithFlags.enabled?(:kura_cache, for: account)
  end

  @doc """
  Whether the account's Tuist-managed Kura nodes should join the same
  mutually-authenticated mesh as its self-hosted nodes. When enabled, managed
  nodes are issued peer certificates from the account's mesh CA so they trust,
  and are trusted by, the customer's self-hosted nodes.
  """
  def kura_mesh_bridging_enabled?(account) do
    FunWithFlags.enabled?(:kura_mesh_bridging, for: account)
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.User do
    def id(%{id: id}) do
      "user:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.Account do
    def id(%{id: id}) do
      "account:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Projects.Project do
    def id(%{id: id}) do
      "project:#{id}"
    end
  end
end
