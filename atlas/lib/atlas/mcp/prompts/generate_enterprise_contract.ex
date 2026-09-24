defmodule Atlas.MCP.Prompts.GenerateEnterpriseContract do
  @moduledoc """
  MCP prompt that expands into the workflow for preparing either a standalone
  order form or a complete enterprise-contract package for an Atlas account.
  """

  @behaviour EMCP.Prompt

  alias Atlas.Accounts.Account
  alias Atlas.Contracts
  alias Atlas.MCP.AccountLookup

  @impl EMCP.Prompt
  def name, do: "generate_enterprise_contract"

  @impl EMCP.Prompt
  def description,
    do:
      "Prepare a standalone order form or a complete enterprise-contract package for an Atlas account using the templates Atlas ships."

  @impl EMCP.Prompt
  def arguments do
    [
      %{
        name: "account",
        description: "Account handle, account_key, or UUID to contract with.",
        required: true
      },
      %{
        name: "contract_id",
        description: "Contract identifier used for folder/file naming (e.g. \"Acme-0426\"). Optional.",
        required: false
      },
      %{
        name: "template_set",
        description: "Template set folder name (e.g. \"2026-02\"). Defaults to the current set.",
        required: false
      },
      %{
        name: "document_scope",
        description:
          ~s(Set to "order_form" for one standalone order form or "contract_package" for the Master Services Agreement, annexes, and one order form. Defaults to "contract_package".),
        required: false
      }
    ]
  end

  @impl EMCP.Prompt
  def template(_conn, args) do
    template_set = args["template_set"] || Contracts.default_template_set()
    contract_id = args["contract_id"] || "TBD"
    account_arg = args["account"]
    account_block = render_account_block(account_arg)
    document_scope = document_scope(args)

    text = render_template(account_arg, account_block, template_set, contract_id, document_scope)

    %{
      description: workflow_description(document_scope),
      messages: [
        %{
          role: "user",
          content: %{type: "text", text: text}
        }
      ]
    }
  end

  defp render_account_block(account_arg) when is_binary(account_arg) do
    case resolve_account(account_arg) do
      {:ok, %Account{} = account} ->
        """
        - Resolved account: #{account.name}#{legal_name_suffix(account)}
        - account_key: #{account.account_key}
        - account_id: #{account.id}
        """

      _other ->
        """
        - Could not resolve "#{account_arg}" against any account in Atlas. Verify the handle, account_key, or UUID with the user, then call `get_account` directly.
        """
    end
  end

  defp render_account_block(_account_arg), do: "- (no account provided)\n"

  defp legal_name_suffix(%Account{legal_name: nil}), do: ""
  defp legal_name_suffix(%Account{legal_name: ""}), do: ""
  defp legal_name_suffix(%Account{legal_name: legal_name}), do: " (legal name: #{legal_name})"

  defp resolve_account(arg) do
    candidates =
      if uuid?(arg) do
        [%{"account_id" => arg}, %{"account_key" => arg}, %{"handle" => arg}]
      else
        [%{"account_key" => arg}, %{"handle" => arg}]
      end

    Enum.find_value(candidates, {:error, :not_found}, fn lookup ->
      case AccountLookup.resolve(lookup) do
        {:ok, account} -> {:ok, account}
        _other -> false
      end
    end)
  end

  defp uuid?(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _uuid} -> true
      :error -> false
    end
  end

  defp uuid?(_value), do: false

  defp document_scope(%{"document_scope" => "order_form"}), do: :order_form
  defp document_scope(_args), do: :contract_package

  defp workflow_description(:order_form), do: "Workflow for preparing a standalone order form."
  defp workflow_description(:contract_package), do: "Workflow for preparing a fresh enterprise-contract package."

  defp render_template(account_arg, account_block, template_set, contract_id, document_scope) do
    """
    You are preparing #{artifact_description(document_scope)} for `#{account_arg}`.

    # Inputs
    #{account_block}- Template set: `#{template_set}`
    #{contract_id_instruction(document_scope, contract_id)}

    # Source of truth
    - Customer commercial data lives in Atlas. Call `get_account` for the full bundle (legal name, billing address, signatory, currency, current_value, next_renewal_date, contacts, etc.). Use what is on the account; ask the user for anything missing rather than inventing legal or billing data.
    - Explicit values in the user's current request override pasted conversation context. Both override older values stored in Atlas.
    - Templates are served by Atlas. Call `list_contract_templates` (template_set = `#{template_set}`) to see the available files, then call `get_contract_template` for each one you need. That tool attaches the official Word template directly as an embedded resource. Use the attached resource rather than browser, desktop-control, or terminal hand-offs. Its signed `download_url` is only a fallback for clients with local file access.

    # Templates to fetch (template_set = `#{template_set}`)
    #{templates_to_fetch(document_scope)}

    # Standard procedure
    #{standard_procedure(document_scope)}

    #{package_edit_instructions(document_scope)}

    # Hosted vs Self-hosted
    Pick the order form based on the deal's hosting model. The account record may or may not carry this flag explicitly. If you cannot determine it from `get_account` or context, ASK THE USER which variant to use.

    - **Tuist-hosted** uses `order-form-tuist-hosted.docx`:
      - Opening service paragraph refers to `Tuist Services`.
      - Fixed-fee prose describes the hosted product bundle (remote cache, analytics, insights, previews, future hosted features).
      - Keep the usage-based section only if the commercial deal actually uses it. Otherwise remove the empty rows and unused placeholder text.
      - Default the notes block to `No notes` when there are no negotiated deviations.

    - **Self-hosted** uses `order-form-self-hosted.docx`:
      - Opening service paragraph reads `the rights to self-host Tuist Server on-premise in Customer's own infrastructure`.
      - Pricing summary intro lists only the applicable sections (typically just fixed fees).
      - Remove the usage-based heading, the usage table, and any empty placeholder summary rows.
      - Fixed-fee prose describes the annual self-hosted license economics and any included support commitment, not hosted-server features.
      - Keep the notes section only when there are negotiated deviations.

    # Order form fills (both variants)
    Field sources (latest active commercial term on the account unless noted):
    - `Start Date`: start date of the active term
    - `Initial Term`: from the active term; if a negotiated description exists (e.g. `24 months and yearly payment`), keep that exact wording
    - `Renewal Term`: the negotiated commercial term, not a hardcoded default
    - `Price per seat`, `Seats`, `Discount`, `Total`: from the active term
    - `Customer`, `Company`, `Sold to`, `Bill to`, address, tax / VAT: from `get_account`, email context, or the user

    Useful defaults when the user does not override them:
    - Payment method: `Wire Transfer`
    - Billing frequency: `One time in advance`

    # Output
    #{output_instructions(document_scope, contract_id)}

    If any required legal, billing, or commercial field cannot be derived, ASK THE USER before filling.
    """
  end

  defp artifact_description(:order_form), do: "a standalone order form"
  defp artifact_description(:contract_package), do: "a fresh enterprise-contract package"

  defp contract_id_instruction(:order_form, contract_id) do
    """
    - Optional contract identifier for output naming: `#{contract_id}`
      When it is `TBD`, use the customer name for the filename instead of blocking on this value.
    """
  end

  defp contract_id_instruction(:contract_package, contract_id) do
    """
    - Contract identifier (used for the local folder and zip name): `#{contract_id}`
      If `TBD`, ask the user. Convention is `<Customer>-MMYY`, e.g. `Acme-0426`.
    """
  end

  defp templates_to_fetch(:order_form) do
    """
    - One of `order-form-tuist-hosted.docx` or `order-form-self-hosted.docx` (see "Hosted vs Self-hosted").
    - Do not fetch the MSA or annexes unless the user expands the requested scope.
    """
  end

  defp templates_to_fetch(:contract_package) do
    """
    - `msa.docx`
    - `annex-2-dpa.docx`
    - `annex-3-daa.docx`
    - `annex-4-sla.docx`
    - One of `order-form-tuist-hosted.docx` or `order-form-self-hosted.docx` (see "Hosted vs Self-hosted")
    """
  end

  defp standard_procedure(:order_form) do
    """
    1. Call `get_account` and reconcile its fields with the user's current request.
    2. Call `list_contract_templates` to confirm the available files.
    3. Determine the hosting model, then call `get_contract_template` for exactly one order-form template.
    4. Fill the attached template using the rules in "Order form fills" while preserving its layout.
    5. Do a final placeholder sweep and return the filled Word document as an output.
    """
  end

  defp standard_procedure(:contract_package) do
    """
    1. Call `get_account` and reconcile its fields with the user's current request.
    2. Call `list_contract_templates` to confirm the available files.
    3. Call `get_contract_template` for each file you need and use each attached Word resource directly.
    4. Fill the MSA (see "MSA edits").
    5. Copy the DPA, DAA, and SLA verbatim. Only edit them when the user explicitly asks for negotiated deviations.
    6. Fill the chosen order form using the rules in "Order form fills".
    7. Do a final manual placeholder sweep across all filled files and return them as outputs.
    """
  end

  defp package_edit_instructions(:order_form), do: ""

  defp package_edit_instructions(:contract_package) do
    """
    # MSA edits
    The February 2026 MSA template has two standard edits:
    - Replace the customer block in the body (the paragraph that reads `[■Customer Name and Address]`) with the customer's legal name and full address.
    - Replace `Contract No. [insert]` in BOTH the normal header AND the first-page contract-number header. Easy to miss; verify both.
    Keep the rest of the MSA verbatim unless the user explicitly requests redlines.

    # Annexes (DPA, DAA, SLA)
    The imported templates do not carry placeholder tokens. Copy them as-is, keep titles, numbering, and layout untouched, and only edit when the user requests negotiated deviations.
    """
  end

  defp output_instructions(:order_form, contract_id) do
    """
    - One filled Word order form named from `#{contract_id}` or the customer when the contract identifier is unavailable.
    - Return the document through the client's normal file-output mechanism.
    """
  end

  defp output_instructions(:contract_package, contract_id) do
    """
    - Filled Word files named under the `#{contract_id}` contract identifier.
    - Return every document through the client's normal file-output mechanism.
    - When the client has a local filesystem, also place the files under `./contracts/#{contract_id}/` and zip them to `./contracts/#{contract_id}.zip`.
    """
  end
end
