# Release History

## [1.1.0](https://www.github.com/googleapis/google-auth-library-ruby/compare/googleauth/v1.0.0...googleauth/v1.1.0) (2021-10-24)


### Features

* Support short-lived tokens in Credentials ([9d7051c](https://www.github.com/googleapis/google-auth-library-ruby/commit/9d7051cff4d5e191a5d6756a068e8be539934f0d))

## [1.0.0](https://www.github.com/googleapis/google-auth-library-ruby/compare/googleauth/v0.17.1...googleauth/v1.0.0) (2021-09-27)

Bumped version to 1.0.0. Releases from this point will follow semver.

* Allow dependency on future 1.x versions of signet ([9e17a24](https://www.github.com/googleapis/google-auth-library-ruby/commit/9e17a24bf97cb52f09756c624b4dc6e18dc79493))
* Prevented gcloud from authenticating on the console when getting the gcloud project ([9902503](https://www.github.com/googleapis/google-auth-library-ruby/commit/990250345d6af31de1066c08c0b3b42692ae263c))

## [0.17.1](https://www.github.com/googleapis/google-auth-library-ruby/compare/googleauth/v0.15.0...googleauth/v0.17.1) (2021-09-01)

* Updates to gem metadata ([fb5e56d](https://www.github.com/googleapis/google-auth-library-ruby/commit/fb5e56dad1e6ed6afd4f9b5c626e5e1495e48343))

## [0.17.0](https://www.github.com/googleapis/google-auth-library-ruby/compare/google-auth-library-ruby/v0.16.2...google-auth-library-ruby/v0.17.0) (2021-07-30)

* Allow scopes to be self-signed into jwts ([e67ce40](https://www.github.com/googleapis/google-auth-library-ruby/commit/e67ce40f919b7eb3723c2ec95f5b8d58315ab1ee))

## [0.16.2](https://www.github.com/googleapis/google-auth-library-ruby/compare/google-auth-library-ruby/v0.16.1...google-auth-library-ruby/v0.16.2) (2021-04-28)

* Stop attempting to get the project from gcloud when applying self-signed JWTs ([#317](https://www.github.com/googleapis/google-auth-library-ruby/issues/317)) ([39258ca](https://www.github.com/googleapis/google-auth-library-ruby/commit/39258cacafa5c770fb40d99075a97b8e6427adba))

## [0.16.1](https://www.github.com/googleapis/google-auth-library-ruby/compare/google-auth-library-ruby/v0.16.0...google-auth-library-ruby/v0.16.1) (2021-04-01)

* Accept application/text content-type for plain idtoken response ([4948ebb](https://www.github.com/googleapis/google-auth-library-ruby/commit/4948ebb3ca151e9f0433585a41bad6f415416b2d))

## [0.16.0](https://www.github.com/googleapis/google-auth-library-ruby/compare/v0.15.1...v0.16.0) (2021-03-04)

* Drop support for Ruby 2.4 and add support for Ruby 3.0 ([6644806](https://www.github.com/googleapis/google-auth-library-ruby/commit/6644806ab47cea6d08e1901c2ed808e53a579bc3))

## [0.15.1](https://www.github.com/googleapis/google-auth-library-ruby/compare/v0.15.0...v0.15.1) (2021-02-08)

* Fix crash when using a client credential without any paths or env_vars set ([#296](https://www.github.com/googleapis/google-auth-library-ruby/issues/296)) ([c971c1a](https://www.github.com/googleapis/google-auth-library-ruby/commit/c971c1ad2d7730c0f5b389d533a972be32fbaf49))

## [0.15.0](https://www.github.com/googleapis/google-auth-library-ruby/compare/v0.14.0...v0.15.0) (2021-01-26)

* Credential parameters inherit from superclasses ([4fa4720](https://www.github.com/googleapis/google-auth-library-ruby/commit/4fa47206dbd62f8bbdd1b9d3721f6baee9fd1d62))
* Service accounts apply a self-signed JWT if scopes are marked as default ([d22acb8](https://www.github.com/googleapis/google-auth-library-ruby/commit/d22acb8a510e6711b5674545c31a4816e5a9168f))

* Retry fetch_access_token when GCE metadata server returns unexpected errors ([cd9b012](https://www.github.com/googleapis/google-auth-library-ruby/commit/cd9b0126d3419b9953982f71edc9e6ba3f640e3c))
* Support correct service account and user refresh behavior for custom credential env variables ([d2dffe5](https://www.github.com/googleapis/google-auth-library-ruby/commit/d2dffe592112b45006291ad9a57f56e00fb208c3))

## 0.14.0 / 2020-10-09

* Honor GCE_METADATA_HOST environment variable
* Fix errors in some environments when requesting an access token for multiple scopes

## 0.13.1 / 2020-07-30

* Support scopes when using GCE Metadata Server authentication ([@ball-hayden][])

## 0.13.0 / 2020-06-17

* Support for validating ID tokens.
* Fixed header application of ID tokens from service accounts.

## 0.12.0 / 2020-04-08

* Support for ID token credentials.
* Support reading quota_id_project from service account credentials.

## 0.11.0 / 2020-02-24

* Support Faraday 1.x.
* Allow special "postmessage" value for redirect_uri.

## 0.10.0 / 2019-10-09

Note: This release now requires Ruby 2.4 or later

* Increase metadata timeout to improve reliability in some hosting environments
* Support an environment variable to suppress Cloud SDK credentials warnings
* Make the header check case insensitive
* Set instance variables at initialization to avoid spamming warnings
* Pass "Metadata-Flavor" header to metadata server when checking for GCE

## 0.9.0 / 2019-08-05

* Restore compatibility with Ruby 2.0. This is the last release that will work on end-of-lifed versions of Ruby. The 0.10 release will require Ruby 2.4 or later.
* Update Credentials to use methods for values that are intended to be changed by users, replacing constants.
* Add retry on error for fetch_access_token
* Allow specifying custom state key-values
* Add verbosity none to gcloud command
* Make arity of WebUserAuthorizer#get_credentials compatible with the base class

## 0.8.1 / 2019-03-27

* Silence unnecessary gcloud warning
* Treat empty credentials environment variables as unset

## 0.8.0 / 2019-01-02

* Support connection options :default_connection and :connection_builder when creating credentials that need to refresh OAuth tokens. This lets clients provide connection objects with custom settings, such as proxies, needed for the client environment.
* Removed an unnecessary warning about project IDs.

## 0.7.1 / 2018-10-25

* Make load_gcloud_project_id module function.

## 0.7.0 / 2018-10-24

* Add project_id instance variable to UserRefreshCredentials, ServiceAccountCredentials, and Credentials.

## 0.6.7 / 2018-10-16

* Update memoist dependency to ~> 0.16.

## 0.6.6 / 2018-08-22

* Remove ruby version warnings.

## 0.6.5 / 2018-08-16

* Fix incorrect http verb when revoking credentials.
* Warn on EOL ruby versions.

## 0.6.4 / 2018-08-03

* Resolve issue where DefaultCredentials constant was undefined.

## 0.6.3 / 2018-08-02

* Resolve issue where token_store was being written to twice

## 0.6.2 / 2018-08-01

* Add warning when using cloud sdk credentials

## 0.6.1 / 2017-10-18

* Fix file permissions

## 0.6.0 / 2017-10-17

* Support ruby-jwt 2.0
* Add simple credentials class

## 0.5.3 / 2017-07-21

* Fix file permissions on the gem's `.rb` files.

## 0.5.2 / 2017-07-19

* Add retry mechanism when fetching access tokens in `GCECredentials` and `UserRefreshCredentials` classes.
* Update Google API OAuth2 token credential URI to v4.

## 0.5.1 / 2016-01-06

* Change header name emitted by `Client#apply` from "Authorization" to "authorization" ([@murgatroid99][])
* Fix ADC not working on some windows machines ([@vsubramani][])
[#55](https://github.com/google/google-auth-library-ruby/issues/55)

## 0.5.0 / 2015-10-12

* Initial support for user credentials ([@sqrrrl][])
* Update Signet to 0.7

## 0.4.2 / 2015-08-05

* Updated UserRefreshCredentials hash to use string keys ([@haabaato][])
[#36](https://github.com/google/google-auth-library-ruby/issues/36)

* Add support for a system default credentials file. ([@mr-salty][])
[#33](https://github.com/google/google-auth-library-ruby/issues/33)

* Fix bug when loading credentials from ENV ([@dwilkie][])
[#31](https://github.com/google/google-auth-library-ruby/issues/31)

* Relax the constraint of dependent version of multi_json ([@igrep][])
[#30](https://github.com/google/google-auth-library-ruby/issues/30)

* Enables passing credentials via environment variables. ([@haabaato][])
[#27](https://github.com/google/google-auth-library-ruby/issues/27)

## 0.4.1 / 2015-04-25

* Improves handling of --no-scopes GCE authorization ([@tbetbetbe][])
* Refactoring and cleanup ([@joneslee85][])

## 0.4.0 / 2015-03-25

* Adds an implementation of JWT header auth ([@tbetbetbe][])

## 0.3.0 / 2015-03-23

* makes the scope parameter's optional in all APIs. ([@tbetbetbe][])
* changes the scope parameter's position in various constructors. ([@tbetbetbe][])

[@dwilkie]: https://github.com/dwilkie
[@haabaato]: https://github.com/haabaato
[@igrep]: https://github.com/igrep
[@joneslee85]: https://github.com/joneslee85
[@mr-salty]: https://github.com/mr-salty
[@tbetbetbe]: https://github.com/tbetbetbe
[@murgatroid99]: https://github.com/murgatroid99
[@vsubramani]: https://github.com/vsubramani
[@ball-hayden]: https://github.com/ball-hayden
