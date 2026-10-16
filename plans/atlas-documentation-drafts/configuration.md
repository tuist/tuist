## Sign-in

| Setting | Meaning |
| --- | --- |
| `GOOGLE_CLIENT_ID` | Client identifier for your Google sign-in application. |
| `GOOGLE_CLIENT_SECRET` | Secret for that application. Keep it private. |
| `ATLAS_ALLOWED_EMAIL_DOMAIN` | Allowed email domain, normalized to lowercase. Also sets Google's account-picker hint. Defaults to the existing configured domain when unset. |

The allowed domain controls admission, not role assignment. A blank or malformed override prevents startup. See the [first administrator guide](/docs/first-administrator) for the initial access grant.

## Production keys and database

| Setting | Meaning |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection for this installation. |
| `SECRET_KEY_BASE` | Independent secret for the application's signed sessions and tokens. |
| `GUARDIAN_SECRET_KEY` | Independent secret for authentication tokens. |
| `ENCRYPTION_KEY` | Base64-encoded key for encrypted application data. |

These settings are required in production. Preserve encryption keys with your backups; replacing a key without a migration can make stored data unreadable.

## First administrator command

`ATLAS_BOOTSTRAP_ADMIN_EMAIL` selects an existing signed-in user for the one-time operator command. It is not a web setting and never creates a user. The command refuses after initialization or when an administrator already exists.

See [First administrator](/docs/first-administrator) for command examples and recovery boundaries.

## Provider configuration

This reference covers the installation slice currently implemented. Integration settings are not yet consolidated into a supported standalone configuration contract. Review the [integration reference](/docs/integrations) and the application configuration before enabling workers or delivery providers.
