# Stable (3.8.x)


3.10.0
------
- Add headers to request proto

3.9.0
-----
- Performance improvements

3.8.0
-----
- Map types now supported (#367)

3.7.0 (pre3)
-----------
- Evaluate extension fields in code generation (#329)
- Change the ping port to use ms timeout and make the default 200ms (#332)
- Fix build failures caused by Rails 5 requirement of Ruby 2.2.2 (#343)
- Add functional tests (#346)
- Extract client and server (#347) (#348)
- BUG: Fix decoding of packed fields (#349)
- Add support for custom file options (#350)
- BUG: enum_for_tags returns nil if tag nil (#352)
- Update rubocop and fix cops (#353)
- Optimization for varint (#356)
- Add support for custom field options (#357)
- Add support for custom enum options (#359)
- Add support for custom message options (#360)
- Acceptable check is not needed most places as coerce runs the same logic (#361)
- Encode straight to stream without intermediary copies (#362)
- Move dynamic rule checks to the initialize method (#363)
- Add support for custom service options (#364)
- Add support for custom method options (#365)
- Upcase enum default (#366)

3.7.0 (pre2)
-----------
- BUG: Track if a repeated field has been deliberately set (#325)

3.7.0 (pre1)
-----------
- BUG: Revert to old behavior for setting repeated fields to nil
- BUG: Set binmode for protoc-gen-ruby STDIN and STDOUT to compile proto files on Windows
- Make all things Optionable and fix requires

3.7.0 (pre0)
-----------
- Add `PB_USE_RAW_RPC_NAMES` option to preserve raw RPC name (since #underscore can be lossy).
- Add `PB_ENUM_UPCASE` option to generate enum values as upcased.
- Clean up dynamic code generation in prep for extension namespacing.
- Namespace extension fields.
- Field values should be stored via their fully qualified names
- Refresh google/protobuf/descriptor.{proto,pb.rb}
- Properly encode and decode negative enum values.

# Stable (3.6.x)

3.6.9
--------
- Make protobuf serivce directory pluggable.

3.6.7
-----
- An issue was reported with the encode memoization added in #293 with using any array modification
method on repeated fields. Remove memoization on encode (#305) until we can find a better solution.

3.5.5
--------
- Add native Varint for MRI.

3.5.4
--------
- Ensures ActiveSupport::Deprecation does not get a stack trace when deprecations are disabled.

3.5.3
--------
- Optimized get_extension_field and get_field calls.

3.5.2
--------
- Optimized valid_tag?, enums_for_tag and enums_for_tags

3.5.1
--------
- Adds compatibility for Rails 4.2+ as CLI options were broken
- Fixes bug with MRI and "dead" thread in zmq broker
- Fixes Rubocop compatability with new version

3.0.4
--------

- Raise specific MethodNotFound when service class doesn't respond to (publicly implement)
    the rpc method called from the client. Stop rescuing all NoMethodError's thrown
    by service implementations. [#193, @liveh2o]

3.0.3
---------

- Fix recursive memory/cpu growth issue when calling class-level `Message.to_json`. [#190]

3.0.2
---------

- Queue requests at the broker when concurrent requests hit the ZMQ server, distribute to
    worker threads on each turn of the read poll loop. [#189, @abrandoned, @liveh2o]

3.0.1
---------

- Fix NoMethodError that can occur when serializing a message with a missing required field. [#187, @abrandoned]

3.0.0
---------

A lot has changed since the last stable v2.8.12. For all the relevant changes,
see the closed [pull requests and issues list in github](https://github.com/localshred/protobuf/issues?milestone=1&state=closed).
Below is a high-level list of fixes, deprecations, breaking changes, and new APIs.

### EventMachine is dead, Long live EventMachine

The EventMachine client and server have been removed from this gem. They code was far
too error prone and flawed to feasibly support going forward. It's recommended
to switch to the socket implementation (using `PB_CLIENT_TYPE` and `PB_SERVER_TYPE` of `socket`)
for a painless switchover. The ZMQ implementation is much more performant but
does have a dependency on libzmq.

### Server Middlewares

The server/dispatcher stack has been converted to the Middleware pattern!
Exception handling (#162, #164), Request decoding (#160, #166), Response encoding (#161, #167),
Logging and stats (#163), and Method dispatch (#159) have all been extracted into their
own Middlewares to greatly simplify testing and further development of the server
stack, furthering our preparations for removing the socket implementations (zmq, socket)
into their own gems in version 4.0. Major props to @liveh2o for [tackling this beast](https://github.com/localshred/protobuf/tree/master/lib/protobuf/rpc/middleware).

#### Bug Fixes

- Resolve DNS names (e.g. localhost) when using ZMQ server. [#46, reported by @reddshack]
- Switched to hash based value storage for messages to fix large field tag memory issues. [#118, #165]
- `Enum.fetch` used to return an enum of any type if that is the value passed in. [#168]

#### Deprecations

__!! NOTE: These deprecated methods will be removed in v3.1. !!__

- Deprecated `BaseField#type` in favor of `#type_class`.
- Deprecated `Message.get_ext_field_by_name` in favor of `.get_extension_field` or `.get_field(name_or_tag, true)`.
- Deprecated `Message.get_ext_field_by_tag,` in favor of `.get_extension_field` or `.get_field(name_or_tag, true)`.
- Deprecated `Message.get_field_by_name,` in favor of `.get_field`.
- Deprecated `Message.get_field_by_tag,` in favor of `.get_field`.
- Deprecated `Enum.enum_by_value` in favor of `.enum_for_tag`.
- Deprecated `Enum.name_by_value` in favor of `.name_for_tag`.
- Deprecated `Enum.get_name_by_tag` in favor of `.name_for_tag`.
- Deprecated `Enum.value_by_name` in favor of `.enum_for_name`.
- Deprecated `Enum.values` in favor of `.enums`. Beware that `.enums` returns an array where `.values` returns a hash.
   Use `.all_tags` if you just need all the valid tag numbers. In other words, don't do this anymore: `MyEnum.values.values.map(&:to_i).uniq`.

#### Breaking Changes

- Require Active Support 3.2+. [#177]
- All files/classes relating to the EventMachine client and server are gone. Use `PB_CLIENT_TYPE` and `PB_SERVER_TYPE` of `socket` instead. [#116]
- Cleaned up the `Enum` class, deprecating/renaming most methods. tl;dr, just use `MyEnum.fetch`.
   See #134 for more comprehensive documentation about which methods are going and away and which are being renamed. [#134]
- Pulled `EnumValue` into `Enum`. The `EnumValue` class no longer exists. Use `Enum` for type-checking instead. [#168].
- Removed previously deprecated `bin/rprotoc` executable. Use `protoc --ruby_out=...` instead. [13fbdb9]
- Removed previously deprecated `Service#rpc` method. Use `Service#env#method_name` instead. [f391294]
- Changed the `Service#initialize` to take an `Env` object instead of separate request, method, and client parameters. [6c61bf72]
- Removed attribute readers for `Service#method_name` and `Service#client_host`. Use `Service#env` to get them instead.
- Removed `lib/protobuf/message/message.rb`. Use `lib/protobuf/message.rb` instead.
- Removed field getters from Message instances (e.g. `Message#get_field_by_name`).
   Use class-level getters instead (see Deprecations section).
- Moved `lib/protobuf/message/decoder.rb` to `lib/protobuf/decoder.rb`. The module is still named `Protobuf::Decoder`.
- Removed `Protobuf::Field::ExtensionFields` class.
- Removed instance-level `max` and `min` methods from all relevant Field classes (e.g. Int32Field, Uint64Field, etc).
   Use class-level methods of the same names instead. [#176, 992eb051]
- `PbError#to_response` no longer receives an argument, instead returning a new `Socketrpc::Response` object. [#147, @liveh2o]
- The Server module has been stripped of almost all methods, now simply invokes the Middleware stack for each request. [#159, @liveh2o]
- Removed `Protobuf::PROTOC_VERSION` constant now that the compiler supports any protoc version.

#### New APIs

- Added support for [enum `allow_alias` option](https://developers.google.com/protocol-buffers/docs/proto#enum). [#134]
- `Enum.all_tags` returns an array of unique tags. Use it to replace `Enum.values.values.map(&:to_i)` (`Enum.values` is deprecated).
- `Enum.enums` returns an array of all defined enums for that class (including any aliased Enums).
- Reinstated support for symbol primitive field types in generated Message code. [#170]
- `Message.get_field` accepts a second boolean parameter (default false) to return an extension field if found. [#169]
- Mirror existing `Decoder#decode_from(stream)` with `Encoder#encode_to(stream)`. [#169]
- `Server` now invokes the [middleware stack](https://github.com/localshred/protobuf/tree/master/lib/protobuf/rpc/middleware) for request handling. [#159, @liveh2o]
- Added `protobuf:compile` and `protobuf:clean` rake tasks. Simply `load 'protobuf/tasks/compile.rake'` in your Rakefile (see `compile.rake` for arguments and usage). [#142, #143]
- Add `Protobuf::Deprecator` module to alias deprecated methods. [#165]
- Add support for assigning a symbol to a string or bytes field. [#181, @abrandoned]
- Add `first_alive_load_balance` option to rpc server. Pass `PB_FIRST_ALIVE_LOAD_BALANCE`
   as an env variable to the client process to ensure the client asks the server
   if it is alive (able to server requests to clients). [#183, @abrandoned]

2.8.13
---------

- Backport #190 to 2.8 stable series. [#192]

2.8.12
---------

- Fix thread busy access in zmq server/worker. [#151, @abrandoned]

2.8.11
---------

- Default ZMQ server to use inproc protocol instead of tcp (zero-copy between server-broker-worker). [#145, @brianstien]
- Add `broadcast_busy` functionality that removes server from cluster if the workers are full. [#149, @abrandoned]
- Add cli option for `--no-zmq_inproc`. [#149, @abrandoned]
- Add cli option for `--broadcast_busy`. [#149, @abrandoned]

2.8.10
---------

- Allow passing a file extension to compile/clean rake tasks. [#143]

2.8.9
---------

- Deprecated Protobuf::Lifecycle module in favor of using ActiveSupport::Notifications. [#139, @devin-c]
- Modify `$LOAD_PATH` inside descriptors.rb to make it easier for other libraries to write their own compiler plugins using our pre-compiled descriptors. [#141]
- Add protobuf:clean and protobuf:compile rake tasks for use in external libraries to compile source definitions to a destination. [#142]

2.8.8
---------

- ServiceDirectory beacons broadcast on same ip as listening clients. [#133, @devin-c]

2.8.7
---------

- Fire ActiveSupport load hooks when RPC Server and Client classes are loaded. [#126, @liveh2o]
- Prevent infinite loop when doing service lookup from directory. [#125, @brianstien]

2.8.6
---------

- Fix string/byte encoding issue when unicode characters present. Reported by @foxban. This was also backported to v2.7.12. [#120]

2.8.5
----------

- Fix issue where ServiceDirectory lookups were failing when given a class name, breaking the directory load balancing. (#119)

2.8.4
----------

- Fix issue where frozen strings assigned in a repeated field would cause encoding runtime errors. (#117)

2.8.3
----------

- Add Deprecation warning when requiring `protobuf/evented`. Version 3.x will not support the eventmachine transport layer for client or server.

2.8.2
----------

- Remove the <4.0 version constraint on ActiveSupport.

2.8.1
----------

- Improve `ServiceDirectory` lookup speed ~10x, lookups now done in constant time (devin-c).
- Add Timestamp to end of rpc stat log (represents ending time of request processing).
- Set `request_size` in the rpc stat within ZMQ Worker (previously missing).
- Ensure `request_size` and `response_size` are set on rpc stat for client requests.

2.8.0
-----------

- New compiler supports protobuf compilation/runtime with protoc <= v2.5.0 (c++ compiler removed). [#109]
- Deprecated rprotoc in favor of protoc. [0bc9674]
- Added service dynamic discovery to the ZMQ connector and server. [#91, @devin-c]
- No longer creating `-java` platform gem due to removal of c++ compiler.
- Added WTFPL license.

2.7.12
-----------

- Backport string/byte encoding issue when unicode characters present. [code: #122, original issue: #120]

2.0.0
-----------

#### `rprotoc` changes

* New option `--ruby_out` to specify the output directory to place generated ruby files. If not provided, ruby code will not be generated.
* Extends `libprotoc` to hook in directly to google's provided compiler mechanism.
* Removed all previous compiler code including the racc parser, node visitors, etc.
* See `protoc --help` for default options.

#### `rprotoc` generated files changes

* Import `require`s now occur outside of any module or class declaration which solves ruby vm warnings previously seen.
* Empty inherited Message and Enum classes are pre-defined in the file, then reopened and their fields applied. This solves the issue of recursive field dependencies of two or more types in the same file.
* Generated DSL lines for message fields include the fully qualified name of the type (e.g. `optional ::Protobuf::Field::StringField, :name, 1`)
* Support for any combination of `packed`, `deprecated`, and `default` as options to pass to a field definition.
* Services are now generated in the corresponding `.pb.rb` file instead of their own `*_service.rb` files as before.

#### `rpc_server` changes

* Removed `--env` option. The running application or program is solely in charge of ensuring it's environment is properly loaded.
* Removed reading of `PB_CLIENT_TYPE`, `PB_SERVER_TYPE` environment variables. Should use mode switches or custom requires (see below) instead.
* Removed `--client_socket` in favor of using mode switches. This also means client calls made by the `rpc_server` will run as the same connector type as the given mode (socket, zmq, or evented).
* Removed `--pre-cache-definitions` switch in favor of always pre-caching for performance.
* Removed `--gc-pause-serialization` since using `--gc-pause-request` in conjunction was redundant.
* Removed `--client-type` in favor of mode switches.
* Removed `--server-type` in favor of mode switches.
* Added mode switch `--evented`.
* Added `--threads` to specify number of ZMQ Worker threads to use. Ignored if mode is not zmq.
* Added `--print-deprecation-warnings` switch to tell the server whether or not to print deprecation warnings on field usage. Enabled by default.
* See `rpc_server help start` for all options and usage. Note: the `start` task is the default and not necessary when running the `rpc_server`.

#### Message changes

* `Message#get_field` usage should now specify either `Message#get_field_by_name` or `Message#get_field_by_tag`, depending on your lookup criteria.
* Support for STDERR output when accessing a message field which has been defined as `[deprecated=true]`. Deprecated warnings can be skipped by running your application or program with `PB_IGNORE_DEPRECATIONS=1`.
* Significant internal refactoring which provides huge boosts in speed and efficiency both in accessing/writing Message field values, as well as serialization and deserialization routines.
* Refactor `Message#to_hash` to delegate hash representations to the field values, simply collecting the display values and returning a hash of fields that are set. This also affects `to_json` output.

#### Enum changes

* Add `Enum.fetch` class method to polymorphically retrieve an `EnumValue` object.
* Add `Enum.value_by_name` to retrieve the corresponding `EnumValue` to the given symbol name.
* Add `Enum.enum_by_value` to retrieve the corresponding `EnumValue` to the given integer value.

#### RPC Service changes

* `async_responder` paradigm is no longer supported.
* `self.response=` paradigm should be converted to using `respond_with(object)`.
* Significant internal changes that should not bleed beyond the API but which make maintaining the code much easier.

#### RPC Client changes

* In the absence of `PB_CLIENT_TYPE` environment var, you should be requiring the specific connector type specifically. For instance, if you wish to run in zmq mode for client requests, update your Gemfile: `gem 'protobuf', :require => 'protobuf/zmq'`.
* `:async` option on client calls is no longer recognized.

####  Other changes

* Moved files out of `lib/protobuf/common` folder into `lib/protobuf`. Files affected are logger, wire\_type, util. The only update would need to be the require path to these files since the modules were always `Protobuf::{TYPE}`.
