defmodule TuistWeb.API.OIDCController do
  @moduledoc """
  Controller for OIDC token exchange.

  This controller handles the exchange of CI and workload OIDC tokens for
  short-lived Tuist access tokens. Supports built-in CI providers and account-configured workload identities with account-wide CI access.
  """

  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Guardian
  alias Tuist.OIDC
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error

  plug(
    TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags(["OIDC Authentication"])

  @token_ttl_seconds 3600

  operation(:exchange_token,
    summary: "Exchange an OIDC identity token for a Tuist access token.",
    description: """
    Exchange an OIDC token from a built-in CI provider or an account-configured workload identity provider
    for a short-lived Tuist access token.
    """,
    operation_id: "exchangeOIDCToken",
    request_body:
      {"OIDC token exchange request", "application/json",
       %Schema{
         title: "OIDCTokenExchangeRequest",
         type: :object,
         properties: %{
           account_handle: %Schema{
             type: :string,
             minLength: 1,
             maxLength: 255,
             description:
               "Required target Tuist account for custom workload identity providers. A matching account trust policy grants CI access to all current and future projects in that account."
           },
           token: %Schema{
             type: :string,
             description: "The OIDC JWT token from a supported CI or workload identity provider."
           }
         },
         required: [:token]
       }},
    responses: %{
      ok:
        {"Token exchange successful", "application/json",
         %Schema{
           title: "OIDCTokenExchangeResponse",
           type: :object,
           properties: %{
             access_token: %Schema{
               type: :string,
               description: "The Tuist access token to use for API requests."
             },
             expires_in: %Schema{
               type: :integer,
               description: "Token lifetime in seconds."
             }
           },
           required: [:access_token, :expires_in]
         }},
      bad_request: {"Unsupported provider or missing identity claims", "application/json", Error},
      unauthorized: {"Invalid or expired OIDC token", "application/json", Error},
      forbidden: {"No repository-linked projects or ambiguous repository account", "application/json", Error}
    }
  )

  def exchange_token(%{body_params: %{token: token}} = conn, _opts) do
    with {:ok, claims} <- OIDC.claims(token, Map.get(conn.body_params, :account_handle)),
         {:ok, account, project_scope} <- authorized_account(claims),
         {:ok, access_token} <- generate_token(account, project_scope) do
      conn
      |> put_status(:ok)
      |> json(%{
        access_token: access_token,
        expires_in: @token_ttl_seconds
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Invalid OIDC token format"})

      {:error, :unsupported_provider, issuer} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "Unsupported CI provider. Token issuer '#{issuer}' is not supported. Built-in providers: GitHub Actions, CircleCI, and Bitrise. Configure other issuers in account Authentication settings and provide account_handle."
        })

      {:error, :missing_repository_claim} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "OIDC token does not contain required repository information used to verify it with the GitHub project connection."
        })

      {:error, :oidc_account_required} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "Custom OIDC providers require account_handle. Set TUIST_OIDC_ACCOUNT to your Tuist account handle."
        })

      {:error, :token_not_yet_valid} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token is not yet valid"})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token signature verification failed"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token has expired"})

      {:error, :invalid_audience} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token audience is not valid for Tuist"})

      {:error, :jwks_fetch_failed, jwks_uri} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{message: "Failed to fetch JWKS from identity provider: #{jwks_uri}"})

      {:error, :no_projects} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "No projects linked to the repository. Connect your project to GitHub in the Tuist dashboard first."
        })

      {:error, :ambiguous_repository, repository, account_handles} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message:
            "The repository '#{repository}' is linked to projects in multiple Tuist accounts (#{Enum.join(account_handles, ", ")}). Remove the extra connections in the Tuist dashboard so the repository is linked from a single account."
        })

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Token validation failed: #{inspect(reason)}"})
    end
  end

  defp authorized_account(%{provider: :oidc} = identity) do
    with {:ok, account} <- Accounts.oidc_account_by_grants(identity) do
      {:ok, account, %{"all_projects" => true}}
    end
  end

  defp authorized_account(%{repository: repository} = identity) do
    case Projects.projects_by_vcs_repository_full_handle(repository, preload: [:account]) do
      [] ->
        {:error, :no_projects}

      projects ->
        with {:ok, account} <- single_account(projects, identity) do
          {:ok, account, %{"project_ids" => Enum.map(projects, & &1.id)}}
        end
    end
  end

  # A token is scoped to one account, and project access requires the
  # token's account to own the project. If the identity maps to projects in
  # several accounts, no single token can serve every project, so
  # refuse the exchange instead of picking an account by row order.
  defp single_account(projects, %{repository: repository}) do
    case projects |> Enum.map(& &1.account) |> Enum.uniq_by(& &1.id) do
      [account] -> {:ok, account}
      accounts -> {:error, :ambiguous_repository, repository, accounts |> Enum.map(& &1.name) |> Enum.sort()}
    end
  end

  defp generate_token(account, project_scope) do
    claims = Map.merge(%{"type" => "account", "scopes" => ["ci"]}, project_scope)

    case Guardian.encode_and_sign(account, claims, ttl: {@token_ttl_seconds, :second}) do
      {:ok, token, _full_claims} -> {:ok, token}
      error -> error
    end
  end
end
