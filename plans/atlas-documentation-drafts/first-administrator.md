## Sign in first

The first administrator must already have signed in to Atlas using the configured identity provider and allowed domain. The bootstrap command never creates a user.

## Grant access from the deployment

For the Docker deployment, an operator can select the signed-in user and run the image's release command:

```sh
docker compose run --rm -e ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org atlas /app/bin/bootstrap-admin
```

This command requires an image version that includes the first-administrator bootstrap. For a release installed directly on a host, run:

```sh
ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org bin/bootstrap-admin
```

For a source checkout:

```sh
ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org mise exec -- mix run --no-start -e 'Atlas.Release.bootstrap_admin()'
```

Run migrations before this command. Use the exact identity you intend to grant access to. The command starts the repository dependencies without starting the web server or background workers.

## What the command changes

Atlas ensures the Executive role exists and assigns it to the selected user, preserving any existing roles. That role includes administrator permissions. The assignment and an initialization audit event commit in the same transaction.

Concurrent attempts are serialized. The command refuses if an administrator or Executive assignment already exists, or if the initialization event has already been recorded. A missing or ambiguous identity does not consume initialization.

## After initialization

Reload Atlas and open the administrator user directory to manage access. Other users do not gain administrator privileges from signing in.

Removing the administrator does not reopen bootstrap. Recovery and additional administrator access are separate operations; the bootstrap command is deliberately a one-time installation step.
