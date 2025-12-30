# GitHub Copilot Instructions for Code Reviews

This document provides guidelines for GitHub Copilot to assist with code reviews in the Tuist repository.

## Review Checklist

When reviewing pull requests, ensure the following items are addressed:

### Code Quality and Testing
- **Linting**: Verify that the code has been linted using `mise run lint-fix`. Check for any linting errors or warnings.
- **Testing**: Ensure the change is tested via unit testing or acceptance testing, or both. Look for:
  - New test files for new features
  - Updated tests for modified functionality
  - Adequate test coverage for edge cases
  - Tests that follow the project's testing patterns

### Documentation and Communication
- **PR Title**: Enforce that the title follows the conventional commit convention. The title MUST follow this format:
  ```
  <type>(<scope>): <description>
  ```
  
  **Valid scopes**: `app`, `cli`, `handbook`, `server`, `docs`
  
  **Valid types**: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`
  
  **Examples of correct PR titles**:
  - `feat(cli): add support for async test execution`
  - `fix(app): resolve crash when opening project settings` 
  - `docs(handbook): update migration guide for version 4.0`
  - `fix(server): handle rate limiting for API endpoints`
  - `chore(docs): fix typo in configuration section`
  - `feat(server): add support for OAuth authentication`
  - `refactor(cli): improve error handling in build command`
  
  The description should be:
  - Clear and concise
  - Written in present tense
  - Descriptive of the change's impact
- **User-Facing Changes**: For changes that affect users, confirm the documentation has been updated in the relevant places
- **PR Description**: Check that the PR includes:
  - A clear short description of the purpose
  - Steps to test the changes locally
  - A link to the related issue (if applicable)

### Architecture and Patterns
- **Consistency**: Ensure the code architecture and patterns are consistent with the rest of the codebase
- **Code Style**: Verify adherence to Swift best practices and Tuist's coding conventions
- **Modularity**: Check that code is properly organized within the appropriate modules

## Additional Review Guidelines

### Performance Considerations
- Look for potential performance bottlenecks
- Check for efficient use of resources
- Verify no unnecessary computations or allocations

### Security
- Review for potential security vulnerabilities
- Ensure no hardcoded secrets or sensitive information
- Check proper input validation and sanitization

### Error Handling
- Verify proper error handling and recovery
- Check for informative error messages
- Ensure errors are logged appropriately

### Dependencies
- Review any new dependencies for necessity and security
- Check that dependency versions are properly specified
- Verify compatibility with existing dependencies

## Helpful Commands

When reviewing, you may want to suggest running these commands:
- `mise run build` - Build the project

## Review Tone

When providing feedback:
- Be constructive and specific
- Suggest improvements rather than just pointing out issues
- Acknowledge good practices and clever solutions
- Ask clarifying questions when the intent is unclear
