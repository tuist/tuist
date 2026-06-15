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

  alias TuistOps.Environment
  alias TuistOps.JIT.TailscaleClient

  @doc """
  Whether `subject` may request operator access at all — an identity
  gate applied to every grant request, both tiers. Requires an
  `@<operator_email_domain>` address.

  This is defence in depth, NOT the primary boundary. The
  `X-Pomerium-Claim-Email` header it reads is only trustworthy because
  the reason form is reached through Pomerium (Google Workspace OIDC)
  over a tailnet path that must be restricted to the Pomerium proxy —
  on a raw tailnet Service the header is client-controlled. The customer
  server independently binds every grant to a confirmed operator session,
  so a spoofed request still cannot be turned into account access. Keep
  this domain check cheap and dependency-free so read stays self-serve.
  """
  def requester_allowed?(subject) do
    is_binary(subject) and
      String.ends_with?(String.downcase(subject), "@" <> Environment.operator_email_domain())
  end

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
