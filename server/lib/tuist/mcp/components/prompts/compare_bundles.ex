defmodule Tuist.MCP.Components.Prompts.CompareBundles do
  @moduledoc """
  Guides you through comparing two bundles to identify size changes across the artifact tree. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL.
  """

  use Tuist.MCP.Prompt,
    name: "compare_bundles",
    arguments: [
      %{name: "account_handle", description: "The account handle (organization or user)."},
      %{name: "project_handle", description: "The project handle."},
      %{
        name: "base",
        description:
          "Base bundle: an ID, a Tuist dashboard URL, or a branch name. " <>
            "Defaults to the latest bundle on the project's default branch when omitted."
      },
      %{
        name: "head",
        description:
          "Head bundle: an ID, a Tuist dashboard URL, or a branch name. " <>
            "This is the bundle you want to evaluate. When provided without a base, " <>
            "the base defaults to the latest bundle on the project's default branch."
      }
    ]

  @impl EMCP.Prompt
  def description,
    do:
      "Guides you through comparing two bundles to identify size changes across the artifact tree. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}. They are not needed if base or head is a dashboard URL."

  @impl EMCP.Prompt
  def template(_conn, args) do
    base = Map.get(args, "base")
    head = Map.get(args, "head")
    {account_handle, project_handle} = PromptSupport.resolve_project_handles(args)
    default_branch = PromptSupport.resolve_default_branch(account_handle, project_handle)

    %{
      messages: [
        %{
          role: "user",
          content: %{type: "text", text: prompt_text(base, head, account_handle, project_handle, default_branch)}
        }
      ]
    }
  end

  defp prompt_text(base, head, account_handle, project_handle, default_branch) do
    resolution = resolution_section(base, head, account_handle, project_handle, default_branch)

    """
    # Compare Bundles

    Use MCP tools to fetch two bundles and compare their size and artifact composition.

    ## Available MCP tools

    - **list_projects**: List all accessible projects.
    - **list_bundles**: List bundles for a project (supports git_branch filter).
    - **get_bundle**: Get bundle metadata (sizes, version, platforms).
    - **get_bundle_artifact_tree**: Get the full artifact tree for a bundle as a flat list sorted by path. Each artifact includes `artifact_type`, `path`, and `size`.

    ## Workflow

    #{resolution}

    ### 2. Compare top-level sizes

    Compare these fields between the two bundles:
    - **install_size**: The installed size on device. Flag increases over 5%.
    - **download_size**: The download size from the store. Flag increases over 5%.
    - **version**: Note version changes.
    - **supported_platforms**: Note platform changes.

    ### 3. Compare artifact trees

    Use `get_bundle_artifact_tree` for both the base and head bundles. Save each result to a local JSON file so you can operate on the data without further API calls.

    Once you have both artifact trees locally:
    - Match artifacts by `path` between base and head.
    - Calculate size delta for each matched artifact.
    - Identify new artifacts in head that don't exist in base.
    - Identify removed artifacts that were in base but not in head.
    - Sort artifacts by absolute size increase to find the biggest contributors.

    ### Summary format

    Produce a structured summary with:
    1. **Overall**: install_size delta, download_size delta, verdict (acceptable/concerning).
    2. **Top size increases**: up to 10 artifacts with the largest size growth.
    3. **New artifacts**: artifacts added in the head bundle.
    4. **Removed artifacts**: artifacts removed from the base bundle.
    5. **Recommendations**: actionable next steps. Since the developer is likely on the head branch, suggest concrete local fixes (e.g., "remove unused assets in Resources/", "optimize image at path/to/large.png").
    """
  end

  defp resolution_section(base, head, account_handle, project_handle, default_branch) do
    branch = default_branch || "main"

    project_line =
      if account_handle && project_handle,
        do: "Project: `#{account_handle}/#{project_handle}`.\n",
        else: ""

    base_instruction =
      case base do
        nil ->
          "For the **base**, use `list_bundles` with `git_branch=#{branch}` and pick the most recent bundle."

        _ ->
          "For the **base**, use `get_bundle` with `bundle_id=#{base}`."
      end

    head_instruction =
      case head do
        nil ->
          "For the **head**, detect the current git branch (e.g., run `git branch --show-current`). " <>
            "If it differs from `#{branch}`, use `list_bundles` with that branch and pick the most recent bundle. " <>
            "If it matches the base branch, ask the user which bundle to compare."

        _ ->
          "For the **head**, use `get_bundle` with `bundle_id=#{head}`."
      end

    """
    ### 1. Resolve bundles

    #{project_line}#{base_instruction}
    #{head_instruction}
    """
  end
end
