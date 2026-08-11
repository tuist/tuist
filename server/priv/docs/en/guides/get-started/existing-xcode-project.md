---
{
  "title": "Existing Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Add Tuist caching and insights to an existing Xcode project without adopting project generation."
}
---
# Existing Xcode project {#existing-xcode-project}

Keep your existing Xcode project or workspace and add Tuist capabilities one at a time. Project generation is optional for compilation caching, build insights, and test insights.

## What you can add {#what-you-can-add}

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode compilation caching</.localized_link> shares compilation outputs across developer machines and continuous integration environments. It requires Xcode 26 or later.
- <.localized_link href="/guides/features/build-insights/xcode">Xcode build insights</.localized_link> records build duration and performance data.
- <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights</.localized_link> records test results, duration, and failures.

The <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> is different: it replaces modules before a build and requires a generated project. You do not need it to use Xcode's compilation cache.

## Adoption steps {#adoption-steps}

1. <.localized_link href="/guides/install-tuist">Install the Tuist command-line interface</.localized_link> on each developer machine and continuous integration environment that will use Tuist.
2. Run `tuist init` in your project root. Choose the option to integrate the existing Xcode project or workspace, then authenticate and create or select the Tuist project.
3. Start with one capability:
   - For faster builds, follow the <.localized_link href="/guides/features/cache/xcode-cache#setup">Xcode cache setup</.localized_link> and run `tuist setup cache` on every machine that builds the project.
   - For build performance data, add the post-action described in the <.localized_link href="/guides/features/build-insights/xcode">Xcode build insights guide</.localized_link>.
   - For test performance and failure data, add the post-action described in the <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights guide</.localized_link>.
4. When enabling a capability in continuous integration, follow the <.localized_link href="/guides/integrations/continuous-integration#authentication">continuous integration authentication guide</.localized_link> before running the build or test.

## Verify your setup {#verify-your-setup}

Verify the capability you selected before adding another one:

- **Compilation cache:** Build the same revision in two clean environments with diagnostic remarks enabled. Confirm that the later build reports cache hits and that cache activity appears in the project's Xcode cache dashboard.
- **Build insights:** Complete a build, open the project dashboard, and confirm that the build appears with its duration and targets.
- **Test insights:** Complete a test run, open the project dashboard, and confirm that the run lists the executed tests and their results.

Once the first result appears, repeat the setup for teammates and continuous integration or continue with another capability above.
