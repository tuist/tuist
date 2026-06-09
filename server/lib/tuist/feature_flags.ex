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
  Whether cache clients should avoid Kura endpoints for the given account.
  This is intentionally separate from `:kura`, which controls access to the
  managed Kura UI and provisioning surface.
  """
  def kura_cache_opted_out?(account) do
    FunWithFlags.enabled?(:kura_cache_opt_out, for: account)
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
