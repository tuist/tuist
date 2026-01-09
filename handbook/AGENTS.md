# Tuist Handbook

The handbook is a VitePress documentation site covering company policies, procedures, and guidelines.

## Build and Test
- Build (also checks for dead links): `mise run handbook:build`
- Dev server (run from `handbook/`): `mise run handbook:dev`
- Deployment: Cloudflare Pages at handbook.tuist.io

## Directory Structure
```
handbook/
├── .vitepress/
│   └── config.mjs
├── handbook/
│   ├── company/
│   ├── security/
│   ├── engineering/
│   ├── people/
│   ├── marketing/
│   ├── product/
│   ├── support/
│   └── community/
└── package.json
```

## Security Policy Updates
- Follow the standard format: frontmatter, policy owner, effective date, and consistent sections.
- Keep policies practical for a small team.
- Reference the shared responsibility model: `/security/shared-responsibility-model`.
- Infrastructure providers handle their layer; focus on application-layer responsibilities.

## Navigation
- Sidebar should mirror directory structure.
- Add new pages to `.vitepress/config.mjs`.
- Redirects for moved pages live in the buildEnd hook.

## Writing Guidelines
- Clear, concise language for a small technical team.
- Avoid bureaucratic wording; stay practical.
- Use standard GitHub-flavored markdown.

**Frontmatter**
```yaml
---
title: Page Title
titleTemplate: :title | Section | Tuist Handbook
description: Brief description of the page content
---
```

## Common Tasks
**Add a page**
1. Create the markdown file.
2. Add frontmatter.
3. Update `.vitepress/config.mjs`.
4. Run `mise run handbook:build`.
5. Create PR with `@tuist/company` as reviewer.

**Update content**
1. Make changes.
2. Verify internal links.
3. Run `mise run handbook:build`.
4. Create PR with `@tuist/company` as reviewer.

**Move/rename pages**
1. Move/rename file.
2. Update navigation.
3. Add redirect in buildEnd hook if needed.
4. Update internal links.
5. Run `mise run handbook:build`.
6. Create PR with `@tuist/company` as reviewer.
