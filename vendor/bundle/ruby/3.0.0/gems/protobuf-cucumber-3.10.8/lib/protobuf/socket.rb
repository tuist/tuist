##
## Socket Mode
##
#
# Require this file if you wish to run your server and/or client RPC
# with the raw socket handlers. This is the default run mode for bin/rpc_server.
#
# To run with rpc_server either omit any mode switches, or explicitly pass `socket`:
#
#   rpc_server myapp.rb
#   rpc_server --socket myapp.rb
#
# To run for client-side only override the require in your Gemfile:
#
#   gem 'protobuf', :require => 'protobuf/socket'
#
require 'protobuf'
require 'protobuf/rpc/servers/socket/server'
require 'protobuf/rpc/connectors/socket'

::Protobuf.connector_type_class = ::Protobuf::Rpc::Connectors::Socket
