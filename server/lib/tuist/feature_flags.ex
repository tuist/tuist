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
  Whether interactive runner access can be requested from the
  dashboard. Non-production environments expose it with the rest of
  the runners surface; production requires the narrower
  `:runners_interactive` flag.
  """
  def runners_interactive_enabled?(account) do
    not Environment.prod?() or FunWithFlags.enabled?(:runners_interactive, for: account)
  end

  @doc """
  Whether the Kura surface (the per-account Kura servers, the
  self-hosted cache management, and the Usage dashboard) should be
  visible for the given account. Self-hosted deployments (including
  dev/test, which are also not `tuist_hosted?`) always see it, mirroring
  `Tuist.Billing.Entitlements` where the deployment's license is the
  entitlement; the hosted server gates it behind the `:kura` FunWithFlags
  toggle for the actor. Callers should use this rather than checking the
  flag inline so the sidebar entry, the LiveView guards, and the settings
  page all answer the same question.
  """
  def kura_enabled?(account) do
    not Environment.tuist_hosted?() or FunWithFlags.enabled?(:kura, for: account)
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
