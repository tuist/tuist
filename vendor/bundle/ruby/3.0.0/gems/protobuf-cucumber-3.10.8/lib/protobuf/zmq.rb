##
## ZMQ Mode
##
#
# Require this file if you wish to run your server and/or client RPC
# with the ZeroMQ handlers.
#
# To run with rpc_server specify the switch `zmq`:
#
#   rpc_server --zmq myapp.rb
#
# To run for client-side only override the require in your Gemfile:
#
#   gem 'protobuf', :require => 'protobuf/zmq'
#
require 'protobuf'
require 'ffi-rzmq'
require 'protobuf/rpc/servers/zmq/server'
require 'protobuf/rpc/connectors/zmq'

Protobuf.connector_type_class = ::Protobuf::Rpc::Connectors::Zmq
