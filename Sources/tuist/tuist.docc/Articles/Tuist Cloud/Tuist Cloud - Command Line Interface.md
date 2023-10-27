# Command Line Interface

Discover the available commands along with their supported arguments and flags.

## tuist cloud init

This command establishes a new project in Tuist Cloud and integrates the local configuration.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user  |

#### Examples

```sh
# Create a project under your user
tuist cloud init --name cloud-project

# Create a project under a organization
tuist cloud init --name your-cloud-project --owner organization-or-your-username
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--name` | The name of the cloud project you want to initialize | | Yes |
| `--owner` | The name of the username or organization you want to initialize the project with | Your username | No |
| `--url` | A custom URL. This can be useful if you don't use the official `cloud.tuist.io` project | https://cloud.tuist.io  | No |

## tuist cloud auth

#### Properties

This command authenticates the user with Tuist Cloud and saves the session locally.

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any non-authenticated user  |

#### Examples

```sh
tuist cloud auth
```

## tuist cloud session

This command displays the session details for the authenticated user in the current environment. If not authenticated, it provides a corresponding message.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user  |

#### Examples

```sh
tuist cloud session
```

## tuist cloud organization create

This command establishes a new organization. Organizations serve as overarching structures, enabling you to invite members to various projects.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user  |

#### Examples

```sh
tuist cloud organization create my-new-organization
```

#### Arguments

| Argument | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `name` | The name of the organization to create |  | Yes |

## tuist cloud organization show

This command displays a summary of the organization, highlighting its members, their respective roles, and any outstanding invitations.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user  |

#### Examples

```sh
tuist cloud organization show my-organization
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--json` | The output in JSON format | False | No |


## tuist cloud organization delete

> Warning: Deleting an organization is an irreversible action.

This command removes an organization.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization  |

#### Examples

```sh
tuist cloud organization delete my-organization
```

#### Arguments

| Argument | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `name` | The organization to delete |  | Yes |


## tuist cloud organization invite

This command sends an invitation to a new member for an organization. The invitee will only gain access to the organization after accepting the invitation via the email they receive.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization  |

#### Examples

```sh
tuist cloud organization invite my-organization new-member@email.io
```

## tuist cloud organization list

This command displays all the organizations to which the authenticated user has access.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user  |

#### Examples

```sh
tuist cloud organization list
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--json` | The output in JSON format | False | No |


## tuist cloud organization remove invite

This command revokes a pending invitation.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization  |

#### Examples

```sh
tuist cloud organization remove invite my-organization member@email.io
```

## tuist cloud organization remove invite

This command ejects a member from the organization.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization  |

#### Examples

```sh
tuist cloud organization remove member member-username
```

## tuist cloud organization update

This command modifies a member's details in the organization, primarily their role. Organization members can be designated as either admin or user. Admins possess enhanced privileges, such as inviting new members and removing projects. In contrast, users have limited, more passive access to Tuist Cloud features.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization  |

#### Examples

```sh
# Makes member-username admin fo the organization
tuist cloud organization update member member-username --role admin
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--role` | The new member role. Possible values are `admin` and `user` | None | No |

## tuist cloud project create

This command initiates a new project either under the user's account or within an organization.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization if they are creating the project under a organization |

#### Examples

```sh
# Creates a project under the user
tuist cloud project create name-of-project

# Creates a project under a organization
tuist cloud project create name-of-project --organization my-organization
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--organization` | The name of the organization you want to initialize the project with | Your username | No |


## tuist cloud project delete

This command removes a project.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization if they are deleting the project from a organization |

#### Examples

```sh
# Deletes the project from the user account
tuist cloud project delete my-project

# Deletes the project from the organization my-organization
tuist cloud project delete my-project --organization my-organization
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--organization` | The name of the organization to delete the project for | Your username | No |


## tuist cloud project delete

This command displays all the projects to which an account has access.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user |


#### Examples

```sh
tuist cloud project list
``` 

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--json` | The output in JSON format | False | No |

## tuist cloud project token

This command creates a project-specific token for authentication in non-interactive settings such as CI. The generated token should be provided via the `TUIST_CONFIG_CLOUD_TOKEN` environment variable.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorization | Any authenticated user who's admin of the organization if they are deleting the project from a organization |


#### Examples

```sh
tuist cloud project token my-project --organization my-organization
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--organization` | The name of the organization to get project token for | Your username | No |
