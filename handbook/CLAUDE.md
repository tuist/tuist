# Tuist Handbook - Claude Instructions

This document provides guidance for working with the Tuist company handbook.

## Overview

The Tuist handbook is a VitePress-based documentation site that contains company policies, procedures, and guidelines. It's organized into several main sections:

- **Company**: Mission, vision, principles, and leadership information
- **Security**: Comprehensive security policies and procedures
- **Engineering**: Technical standards, practices, and technologies
- **People**: Benefits, values, code of conduct, and how we work
- **Marketing**: Guidelines and case studies
- **Product**: Product development processes
- **Support**: Support processes and procedures
- **Community**: Community-related content

## Technical Details

### Building and Testing

- **Build command**: `mise run handbook:build` (can be run from any directory)
  - This command also verifies that there are no dead links
- **Development server**: `mise run handbook:dev` (from the handbook directory)
- **Deployment**: The handbook is automatically deployed to Cloudflare Pages at handbook.tuist.io

### Directory Structure

```
handbook/
├── .vitepress/
│   └── config.mjs    # Navigation and site configuration
├── handbook/         # Content directory
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

## Working with Security Policies

When creating or modifying security policies:

1. **Follow the standard format**:
   - Include frontmatter with title, titleTemplate, and description
   - Start with policy owner and effective date
   - Use consistent section structure

2. **Standard policy sections**:
   - Purpose
   - Scope
   - Policy Statement
   - Requirements (numbered subsections)
   - Roles and Responsibilities
   - Exceptions
   - Compliance Monitoring
   - Policy Review
   - Version History

3. **Key considerations**:
   - Keep policies practical for a 4-person company
   - Reference the [shared responsibility model](/security/shared-responsibility-model) when discussing infrastructure
   - Infrastructure providers (Fly.io, Supabase, Tigris, Cloudflare) handle their own layer security
   - Focus on application-layer responsibilities

## Navigation Configuration

The site navigation is configured in `.vitepress/config.mjs`:

- The sidebar structure should match the directory structure
- When adding new pages, ensure they're included in the navigation
- Redirects for moved pages are handled in the buildEnd hook

## Content Guidelines

### Writing Style

- Use clear, concise language
- Write for a small, technical team
- Avoid overly bureaucratic language
- Focus on practical implementation

### Frontmatter Format

```yaml
---
title: Page Title
titleTemplate: :title | Section | Tuist Handbook
description: Brief description of the page content
---
```

### Markdown Conventions

- Use standard GitHub-flavored markdown
- Include anchors for major sections
- Use numbered lists for sequential steps
- Use bullet points for non-sequential items

## Important Reminders

1. **Always verify builds**: Run `mise run handbook:build` before committing to ensure:
   - The handbook builds successfully
   - There are no broken links
   - Navigation is properly configured

2. **Security policy updates**: When updating security policies, consider:
   - Impact on the small team size
   - Alignment with shared responsibility model
   - Practical implementation requirements

3. **Infrastructure responsibilities**: Remember that Tuist relies on:
   - Fly.io for application hosting
   - Supabase for database services
   - Tigris for data storage
   - Cloudflare for CDN and edge services

Each provider handles security at their infrastructure layer, while Tuist focuses on application-layer security.

## Common Tasks

### Adding a new page

1. Create the markdown file in the appropriate directory
2. Add proper frontmatter
3. Update `.vitepress/config.mjs` to include it in navigation
4. Run `mise run handbook:build` to verify
5. Commit and create a PR with @tuist/company team as reviewer

### Updating Existing Content

1. Make changes to the markdown file
2. Verify internal links are still valid
3. Run `mise run handbook:build` to test
4. Commit with a descriptive message
5. Create a PR with @tuist/company team as reviewer

### Moving or Renaming Pages

1. Move/rename the file
2. Update navigation in `.vitepress/config.mjs`
3. Add a redirect in the buildEnd hook if needed
4. Update any internal links to the page
5. Run `mise run handbook:build` to verify all links
6. Create a PR with @tuist/company team as reviewer
