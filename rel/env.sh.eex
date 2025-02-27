#!/bin/sh

# configure node for distributed erlang with IPV6 support
if [ ! -z "$TUIST_USE_IPV6" ]; then
  export ERL_AFLAGS="-proto_dist inet6_tcp"
  export ECTO_IPV6="true"
fi

if [ ! -z "$TUIST_HOSTED" ]; then
  export DNS_CLUSTER_QUERY="${FLY_APP_NAME}.internal"
  export RELEASE_DISTRIBUTION="name"
  export RELEASE_NODE="${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP}"
fi
