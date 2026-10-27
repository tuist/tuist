# Handbook

VitePress site for company policies and procedures, deployed to Cloudflare Pages.

- Run `mise run build` from `handbook/` before committing; it checks dead links
  too. Start local previews there with `mise run dev`.
- Add pages to `.vitepress/config.mjs`; keep the sidebar aligned with the content
  structure. For moved pages, update inbound links and the `buildEnd` redirects.
- Use concise, practical language for a small technical team. Request
  `@tuist/company` review on handbook PRs.
- Include `title`, `titleTemplate` (`:title | Section | Tuist Handbook`), and
  `description` in page frontmatter.

## Security policies

Start with the policy owner and effective date. Follow the existing sections:
Purpose, Scope, Policy Statement, Requirements, Roles and Responsibilities,
Exceptions, Compliance Monitoring, Policy Review, and Version History.

Reference `/security/shared-responsibility-model` when discussing infrastructure.
Separate providers' infrastructure responsibilities from Tuist's application-layer
responsibilities, and keep requirements practical for the team.
