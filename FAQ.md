## Frequently Asked Questions

- [Should I add an Xcode project to a gitignore file?](#should-i-add-an-xcode-project-to-a-gitignore-file)
- [What happens when I switch a branch?](#what-happens-when-i-switch-a-branch)

### Should I add an Xcode project to a gitignore file?

Yes, you should. Adding an Xcode project to a `.gitignore` will eliminate the merge conflicts. If you use a Continuous Integration service, add a `tuist generate` command as a step in your build process.

Note that you can still check in an Xcode project as a middle step.

> When you bootstrap a project via `tuist init` command, Tuist will add an Xcode project to `.gitignore` for you.

### What happens when I switch a branch?

When you switch a branch where files have been added or removed, the Xcode project should be re-generated. Unfortunately, it is a manual action. It is recommended to set up a git [post-checkout](https://www.git-scm.com/docs/githooks#_post_checkout) hook. To do so, create a `post-checkout` script in `.git/hooks` folder in your repository:

```bash
#!/bin/sh

tuist generate
```

> Remember to set a `post-checkout` script as executable
