# Command Line Interface

Learn about the commands available and the arguments and flags they support

## tuist cloud init

While Tuist Cloud offers a web interface, we still want to provide a great experience from the CLI. And creating a new Tuist Cloud project is a part of that.


#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user  |

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
| `--name` | The name of the cloud project you want to initialize. | | Yes |
| `--owner` | The name of the username or organization you want to initialize the project with | Your username | No |
| `--url` | A custom URL. This can be useful if you don't use the official `cloud.tuist.io` project | https://cloud.tuist.io  | No |

## tuist cloud auth

#### Properties

Authenticates the user against the Tuist Cloud and persists the session locally.

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any non-authenticated user  |

#### Examples

```sh
tuist cloud auth
```

## tuist cloud session

The command outputs the session of the user authenticated in the current environment, and a message indicating if you are not authenticated otherwises.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user  |

#### Examples

```sh
tuist cloud session
```

## tuist cloud organization create

It creates a new organization. Organizations act as umbrella models to invite other members to projects:

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user  |

#### Examples

```sh
tuist cloud organization create my-new-organization
```

#### Arguments

| Argument | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `name` | The name of the organization to create |  | Yes |

## tuist cloud organization show

It outputs an overview of the organization, including current members, their roles, and pending invites.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user  |

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

Deletes an organization

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization  |

#### Examples

```sh
tuist cloud organization delete my-organization
```

#### Arguments

| Argument | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `name` | The organization to delete |  | Yes |


## tuist cloud organization invite

It invites a new member to an organization. The invited member won't have access to the organization until they accept it through the email that they'll receive.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization  |

#### Examples

```sh
tuist cloud organization invite my-organization new-member@email.io
```

## tuist cloud organization list

Lists all the organizations the authenticated user has access to.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user  |

#### Examples

```sh
tuist cloud organization list
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--json` | The output in JSON format | False | No |


## tuist cloud organization remove invite

It cancels a pending invitation.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization  |

#### Examples

```sh
tuist cloud organization remove invite my-organization member@email.io
```

## tuist cloud organization remove invite

Removes a member from the organization.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization  |

#### Examples

```sh
tuist cloud organization remove member member-username
```

## tuist cloud organization update

It updates a member of the organization. Currently, that means updating their role. Members of the organization can either be `admin` or `user`. Admins have higher privileges than users – they can invite new members, remove projects in an organization, etc. Users have a more passive access to Tuist Cloud features.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization  |

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

It creates a new project under the user account or a organization.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization if they are creating the project under a organization |

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

Deletes a project.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization if they are deleting the project from a organization |

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

Lists all the project an account has access to.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user |


#### Examples

```sh
tuist cloud project list
``` 

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--json` | The output in JSON format | False | No |

## tuist cloud project token

It generates a project-scoped token to authenticate as a project in non-interactive environments like CI. The token generated is expected to be pass through the environment variable `TUIST_CONFIG_CLOUD_TOKEN`.

#### Properties

| Property | Description | 
| ---- | --- |
| Interactivity | Non-interactive |
| Authorized subjects | Any authenticated user that's admin of the organization if they are deleting the project from a organization |


#### Examples

```sh
tuist cloud project token my-project --organization my-organization
```

#### Flags

| Flag | Description | Default | Required |
| -------- | ----------- | ------- | -------- |
| `--organization` | The name of the organization to get project token for | Your username | No |
