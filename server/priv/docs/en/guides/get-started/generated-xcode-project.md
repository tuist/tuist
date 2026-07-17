---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Start managing an Xcode project with Tuist manifests, generation, module caching, and selective testing."
}
---
# Generated Xcode project {#generated-xcode-project}

Use this path when you want Tuist to define and generate your Xcode project. Swift manifests describe projects, targets, dependencies, and schemes, which lets Tuist validate and optimize the complete project graph.

If you want to keep an existing Xcode project or workspace unchanged, use the <.localized_link href="/guides/get-started/existing-xcode-project">existing Xcode project path</.localized_link> instead.

## Adoption steps {#adoption-steps}

1. Follow the <.localized_link href="/tutorials/xcode/create-a-generated-project">generated project tutorial</.localized_link> to install Tuist, initialize a project, add a dependency, generate the Xcode project, and run the application.
2. If you are replacing an existing checked-in Xcode project, follow the <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">Xcode project migration guide</.localized_link>. Migrate incrementally rather than recreating the project from memory.
3. Learn how the <.localized_link href="/guides/features/projects/manifests">manifest files</.localized_link> and <.localized_link href="/guides/features/projects/dependencies">dependencies</.localized_link> model your project.
4. Connect the project to a Tuist account during `tuist init` so shared capabilities can use the project's full handle.
5. Choose the first optimization to add:
   - Follow the <.localized_link href="/guides/features/cache/module-cache">module cache guide</.localized_link> to replace unchanged modules with shared binaries.
   - Follow the <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache guide</.localized_link> to share compilation outputs produced by Xcode 26 or later.
   - Use <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link> to run only tests affected by a change.

Generated schemes include build and test insights automatically. If you define custom schemes, follow the <.localized_link href="/guides/features/build-insights/generated-projects">generated project build insights guide</.localized_link> and the <.localized_link href="/guides/features/test-insights/xcode#generated-projects">generated project test insights instructions</.localized_link>.

## Verify your setup {#verify-your-setup}

Run `tuist generate`, build the generated project in Xcode, and launch the application. This confirms that the manifests and dependencies produce a working project.

Then verify the first optimization you selected:

- **Module cache:** Run `tuist cache`, followed by `tuist generate`. Confirm that generation reuses cached binaries for eligible dependencies.
- **Xcode compilation cache:** Build the same revision in another clean environment and confirm that the later build reports cache hits.
- **Selective testing:** Run `tuist test` successfully, run it again without changing test inputs, and confirm that Tuist skips unaffected test targets.

After the first successful run, move the same commands into continuous integration and configure <.localized_link href="/guides/integrations/continuous-integration#authentication">continuous integration authentication</.localized_link>.
