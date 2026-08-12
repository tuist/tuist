defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment

  @doc """
  Whether the Runners dashboard (and its sub-pages) should be visible
  for the given account. Canary and production require an explicit
  `:runners` FunWithFlags toggle for the actor. Development, test, and
  staging default to enabled.

  This is also the source of truth for co-located private Kura cache
  infrastructure, so enabling runners provides the cache without a second
  operator-managed switch.
  """
  def runners_enabled?(account) do
    not runner_flag_required?() or FunWithFlags.enabled?(:runners, for: account)
  end

  @doc false
  def runners_enabled?(account, %FunWithFlags.Flag{} = flag) do
    not runner_flag_required?() or FunWithFlags.Flag.enabled?(flag, for: account)
  end

  defp runner_flag_required?, do: Environment.env() in [:can, :prod]

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
  Whether a marketing page should render the redesigned version instead of
  the legacy one. The redesign ships page by page: each page gets its own
  boolean flag (`:new_marketing_home`, `:new_marketing_pricing`, ...) that is
  flipped for everyone at once — marketing traffic is mostly anonymous, so
  there is no actor to gate on. Team members can preview a page before the
  flip via the `?design=new` cookie override in `TuistWeb.Marketing.Design`,
  which is also why callers should go through that module rather than
  checking this flag directly.
  """
  def new_marketing_page_enabled?(page) when is_atom(page) do
    FunWithFlags.enabled?(:"new_marketing_#{page}")
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
