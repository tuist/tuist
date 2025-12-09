defmodule TuistWeb.API.OIDCController do
  @moduledoc """
  Controller for OIDC token exchange.

  This controller handles the exchange of CI provider OIDC tokens for
  short-lived Tuist access tokens. Currently supports GitHub Actions.
  """

  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Guardian
  alias Tuist.OIDC.GitHubActions
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags(["OIDC Authentication"])

  @default_ci_scopes [
    "project:cache:read",
    "project:cache:write",
    "project:previews:read",
    "project:previews:write",
    "project:bundles:read",
    "project:bundles:write"
  ]

  @token_ttl_seconds 3600

  operation(:exchange_token,
    summary: "Exchange a CI provider OIDC token for a Tuist access token.",
    description: """
    Exchange an OIDC token from a supported CI provider (currently GitHub Actions)
    for a short-lived Tuist access token.

    The token is validated against the provider's JWKS and matched to projects
    via their VCS connection (repository URL).

    ## GitHub Actions Usage

    In your workflow, request an OIDC token and send it to this endpoint:

    ```yaml
    permissions:
      id-token: write

    steps:
      - name: Get Tuist token
        run: |
          OIDC_TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \\
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=tuist" | jq -r '.value')
          TUIST_TOKEN=$(curl -sS -X POST https://cloud.tuist.dev/api/oidc/token \\
            -H "Content-Type: application/json" \\
            -d "{\"token\": \"$OIDC_TOKEN\"}" | jq -r '.access_token')
          echo "TUIST_TOKEN=$TUIST_TOKEN" >> $GITHUB_ENV
    ```
    """,
    operation_id: "exchangeOIDCToken",
    request_body:
      {"OIDC token exchange request", "application/json",
       %Schema{
         title: "OIDCTokenExchangeRequest",
         type: :object,
         properties: %{
           token: %Schema{
             type: :string,
             description: "The OIDC JWT token from the CI provider."
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
             token_type: %Schema{
               type: :string,
               description: "The token type (always 'Bearer')."
             },
             expires_in: %Schema{
               type: :integer,
               description: "Token lifetime in seconds."
             }
           },
           required: [:access_token, :token_type, :expires_in]
         }},
      unauthorized: {"Invalid or expired OIDC token", "application/json", Error},
      forbidden: {"No projects linked to the repository", "application/json", Error}
    }
  )

  def exchange_token(%{body_params: %{token: token}} = conn, _opts) do
    with {:ok, claims} <- verify_token(token),
         {:ok, projects} <- find_projects_by_repository(claims.repository),
         {:ok, access_token} <- generate_token(projects) do
      conn
      |> put_status(:ok)
      |> json(%{
        access_token: access_token,
        token_type: "Bearer",
        expires_in: @token_ttl_seconds
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Invalid OIDC token format"})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token signature verification failed"})

      {:error, :invalid_issuer} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token issuer not supported"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token has expired"})

      {:error, :missing_repository_claim} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "OIDC token missing repository claim"})

      {:error, :jwks_fetch_failed} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{message: "Failed to fetch JWKS from identity provider"})

      {:error, :no_projects} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "No projects linked to the repository. Connect your project to GitHub in the Tuist dashboard first."})

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Token validation failed: #{inspect(reason)}"})
    end
  end

  defp verify_token(token) do
    GitHubActions.verify(token)
  end

  defp find_projects_by_repository(repository) do
    case Projects.projects_by_vcs_repository_full_handle(repository, preload: [:account]) do
      [] -> {:error, :no_projects}
      projects -> {:ok, projects}
    end
  end

  defp generate_token(projects) do
    account = hd(projects).account
    project_ids = Enum.map(projects, & &1.id)

    claims = %{
      "type" => "account",
      "scopes" => @default_ci_scopes,
      "project_ids" => project_ids
    }

    case Guardian.encode_and_sign(account, claims, ttl: {@token_ttl_seconds, :second}) do
      {:ok, token, _full_claims} -> {:ok, token}
      error -> error
    end
  end
end
