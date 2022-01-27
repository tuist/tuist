# Google Auth Library for Ruby

<dl>
  <dt>Homepage</dt><dd><a href="http://www.github.com/googleapis/google-auth-library-ruby">http://www.github.com/googleapis/google-auth-library-ruby</a></dd>
  <dt>Authors</dt><dd><a href="mailto:temiola@google.com">Tim Emiola</a></dd>
  <dt>Copyright</dt><dd>Copyright © 2015 Google, Inc.</dd>
  <dt>License</dt><dd>Apache 2.0</dd>
</dl>

[![Gem Version](https://badge.fury.io/rb/googleauth.svg)](http://badge.fury.io/rb/googleauth)

## Description

This is Google's officially supported ruby client library for using OAuth 2.0
authorization and authentication with Google APIs.

## Alpha

This library is in Alpha. We will make an effort to support the library, but
we reserve the right to make incompatible changes when necessary.

## Install

Be sure `https://rubygems.org/` is in your gem sources.

For normal client usage, this is sufficient:

```bash
$ gem install googleauth
```

## Example Usage

```ruby
require 'googleauth'

# Get the environment configured authorization
scopes =  ['https://www.googleapis.com/auth/cloud-platform',
           'https://www.googleapis.com/auth/compute']
authorization = Google::Auth.get_application_default(scopes)

# Add the the access token obtained using the authorization to a hash, e.g
# headers.
some_headers = {}
authorization.apply(some_headers)

```

## Application Default Credentials

This library provides an implementation of
[application default credentials][application default credentials] for Ruby.

The Application Default Credentials provide a simple way to get authorization
credentials for use in calling Google APIs.

They are best suited for cases when the call needs to have the same identity
and authorization level for the application independent of the user. This is
the recommended approach to authorize calls to Cloud APIs, particularly when
you're building an application that uses Google Compute Engine.

## User Credentials

The library also provides support for requesting and storing user
credentials (3-Legged OAuth2.) Two implementations are currently available,
a generic authorizer useful for command line apps or custom integrations as
well as a web variant tailored toward Rack-based applications.

The authorizers are intended for authorization use cases. For sign-on,
see [Google Identity Platform](https://developers.google.com/identity/)

### Example (Web)

```ruby
require 'googleauth'
require 'googleauth/web_user_authorizer'
require 'googleauth/stores/redis_token_store'
require 'redis'

client_id = Google::Auth::ClientId.from_file('/path/to/client_secrets.json')
scope = ['https://www.googleapis.com/auth/drive']
token_store = Google::Auth::Stores::RedisTokenStore.new(redis: Redis.new)
authorizer = Google::Auth::WebUserAuthorizer.new(
  client_id, scope, token_store, '/oauth2callback')


get('/authorize') do
  # NOTE: Assumes the user is already authenticated to the app
  user_id = request.session['user_id']
  credentials = authorizer.get_credentials(user_id, request)
  if credentials.nil?
    redirect authorizer.get_authorization_url(login_hint: user_id, request: request)
  end
  # Credentials are valid, can call APIs
  # ...
end

get('/oauth2callback') do
  target_url = Google::Auth::WebUserAuthorizer.handle_auth_callback_deferred(
    request)
  redirect target_url
end
```

### Example (Command Line)

```ruby
require 'googleauth'
require 'googleauth/stores/file_token_store'

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'

scope = 'https://www.googleapis.com/auth/drive'
client_id = Google::Auth::ClientId.from_file('/path/to/client_secrets.json')
token_store = Google::Auth::Stores::FileTokenStore.new(
  :file => '/path/to/tokens.yaml')
authorizer = Google::Auth::UserAuthorizer.new(client_id, scope, token_store)

credentials = authorizer.get_credentials(user_id)
if credentials.nil?
  url = authorizer.get_authorization_url(base_url: OOB_URI )
  puts "Open #{url} in your browser and enter the resulting code:"
  code = gets
  credentials = authorizer.get_and_store_credentials_from_code(
    user_id: user_id, code: code, base_url: OOB_URI)
end

# OK to use credentials
```

### Example (Service Account)

```ruby
scope = 'https://www.googleapis.com/auth/androidpublisher'

authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open('/path/to/service_account_json_key.json'),
  scope: scope)

authorizer.fetch_access_token!
```

You can also use a JSON keyfile by setting the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account_json_key.json
```

```ruby
require 'googleauth'
require 'google/apis/drive_v3'

Drive = ::Google::Apis::DriveV3
drive = Drive::DriveService.new

scope = 'https://www.googleapis.com/auth/drive'

authorizer = Google::Auth::ServiceAccountCredentials.from_env(scope: scope)
drive.authorization = authorizer

list_files = drive.list_files()
```

### Example (Environment Variables)

```bash
export GOOGLE_ACCOUNT_TYPE=service_account
export GOOGLE_CLIENT_ID=000000000000000000000
export GOOGLE_CLIENT_EMAIL=xxxx@xxxx.iam.gserviceaccount.com
export GOOGLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

```ruby
require 'googleauth'
require 'google/apis/drive_v3'

Drive = ::Google::Apis::DriveV3
drive = Drive::DriveService.new

# Auths with ENV vars:
# "GOOGLE_CLIENT_ID",
# "GOOGLE_CLIENT_EMAIL",
# "GOOGLE_ACCOUNT_TYPE", 
# "GOOGLE_PRIVATE_KEY"
auth = ::Google::Auth::ServiceAccountCredentials
  .make_creds(scope: 'https://www.googleapis.com/auth/drive')
drive.authorization = auth

list_files = drive.list_files()

```

### Storage

Authorizers require a storage instance to manage long term persistence of
access and refresh tokens. Two storage implementations are included:

*   Google::Auth::Stores::FileTokenStore
*   Google::Auth::Stores::RedisTokenStore

Custom storage implementations can also be used. See
[token_store.rb](https://googleapis.dev/ruby/googleauth/latest/Google/Auth/TokenStore.html) for additional details.

## Supported Ruby Versions

This library is supported on Ruby 2.5+.

Google provides official support for Ruby versions that are actively supported
by Ruby Core—that is, Ruby versions that are either in normal maintenance or in
security maintenance, and not end of life. Currently, this means Ruby 2.5 and
later. Older versions of Ruby _may_ still work, but are unsupported and not
recommended. See https://www.ruby-lang.org/en/downloads/branches/ for details
about the Ruby support schedule.

## License

This library is licensed under Apache 2.0. Full license text is
available in [LICENSE][license].

## Contributing

See [CONTRIBUTING][contributing].

## Support

Please
[report bugs at the project on Github](https://github.com/google/google-auth-library-ruby/issues). Don't
hesitate to
[ask questions](http://stackoverflow.com/questions/tagged/google-auth-library-ruby)
about the client or APIs on [StackOverflow](http://stackoverflow.com).

[application default credentials]: https://developers.google.com/accounts/docs/application-default-credentials
[contributing]: https://github.com/googleapis/google-auth-library-ruby/tree/main/.github/CONTRIBUTING.md
[license]: https://github.com/googleapis/google-auth-library-ruby/tree/main/LICENSE
