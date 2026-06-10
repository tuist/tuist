defmodule TuistOps.ProjectAccess.Policy do
  @moduledoc """
  Authorization policy for operator access to customer projects.

  Two tiers, two postures:

    * `read` — viewing a customer's dashboard. Self-serve for any
      authenticated operator (Pomerium already gated the reason form
      to `@tuist.dev` Google identities). A logged reason is the only
      requirement; no second human.

    * `admin` — acting with admin privileges on a customer org
      ("sign in as admins"). Treated like a production kubectl write:
      it always needs a **second human** to approve in Slack, and
      that approver must be an Owner or Admin on the tailnet. The
      requester can never self-approve.

  Source of truth for the approver gate is the Tailscale tailnet role
  (`TuistOps.JIT.TailscaleClient.user_role/1`), the same one the JIT
  elevation flow uses — no email lists hardcoded here.
  """

  alias TuistOps.JIT.TailscaleClient

  @doc """
  Read access is self-serve for any authenticated operator. The
  subject comes from Pomerium (`X-Pomerium-Claim-Email`), which only
  forwards `@tuist.dev` Google Workspace identities, so a present
  subject is sufficient — we deliberately do NOT couple read
  availability to the Tailscale API being up.
  """
  def read_self_serve_allowed?(subject), do: is_binary(subject) and byte_size(subject) > 0

  @doc """
  Returns true if `approver_email` may be the second human approving
  an admin-tier request — i.e. their tailnet role is Owner or Admin.
  Members (engineers) and any other role cannot approve admin access
  to a customer org.
  """
  def admin_approver_allowed?(approver_email) when is_binary(approver_email) do
    case TailscaleClient.user_role(approver_email) do
      {:ok, role} -> role in [:owner, :admin]
      _ -> false
    end
  end

  def admin_approver_allowed?(_), do: false
end
