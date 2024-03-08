# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.0
ARG RAILS_ENV=production
ARG APP_REVISION=unknown
ARG TUIST_VERSION=""
ARG ELIXIR_VERSION=1.16.0
ARG OTP_VERSION=26.2.1
ARG DEBIAN_VERSION=buster-20231009-slim
ARG PHX_BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG MIX_ENV="prod"

FROM ${PHX_BUILDER_IMAGE} as phx-builder
ARG MIX_ENV="prod"
RUN apt-get update -y && apt-get install -y build-essential git openssl1.1 \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*
WORKDIR /app
RUN mix local.hex --force && \
    mix local.rebar --force
ENV MIX_ENV=$MIX_ENV
COPY phx/mix.exs phx/mix.lock ./
RUN mix deps.get --only $MIX_ENV
COPY phx/config/config.exs phx/config/${MIX_ENV}.exs config/
COPY phx/priv/secrets/secrets.yml.enc phx/priv/secrets/secrets.yml.enc
RUN mix deps.compile
COPY phx/priv priv
COPY phx/lib lib
COPY phx/assets assets
RUN mix assets.deploy
RUN mix compile
COPY phx/config/runtime.exs config/
COPY phx/rel rel
RUN mix release

FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base-rails

# Rails app lives here
WORKDIR /app

# Install packages needed to build gems and NPM packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl

# Set production environment
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"
ENV TUIST_VERSION=${TUIST_VERSION}

# Install JavaScript dependencies
ARG NODE_VERSION=18.18.0
ARG YARN_VERSION=1.22.17
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build-master

# Throw-away build stage to reduce size of final image
FROM base-rails as build-rails

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ARG APP_REVISION=unknown
ENV APP_REVISION=${APP_REVISION}
ARG TUIST_VERSION=""
ENV TUIST_VERSION=${TUIST_VERSION}

# Install packages needed to build gems and NPM packages
RUN apt-get install --no-install-recommends -y build-essential git libpq-dev libvips pkg-config

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .
RUN rm -rf ./phx

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 TUIST_SECRET_KEY_BASE=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base-rails

# Set the description
LABEL org.opencontainers.image.title="Tuist Cloud"
LABEL org.opencontainers.image.vendor="Tuist GmbH"
LABEL org.opencontainers.image.source=https://github.com/tuist/cloud-on-premise

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ARG APP_REVISION=unknown
ENV APP_REVISION=${APP_REVISION}
ARG TUIST_VERSION=""
ENV TUIST_VERSION=${TUIST_VERSION}
ENV TRAEFIK_VERSION "3.0.0-rc1"
ARG MIX_ENV="prod"
ENV MIX_ENV=$MIX_ENV
ENV SECRETS_PATH="/app/phx/priv/secrets/secrets.yml.enc"

WORKDIR "/app"

# Install packages needed for deployment
RUN apt-get update -y && apt-get install --no-install-recommends -y parallel curl gcc wget libvips postgresql-client libstdc++6 libubsan1 libncurses5 ca-certificates make locales \
    && apt-get clean && rm -f /var/lib/apt/lists/*_* && rm -rf /var/cache/apt/archives

# Install Traefik
RUN curl -L "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_amd64.tar.gz" -o /tmp/traefik.tar.gz && \
    tar -xzf /tmp/traefik.tar.gz -C /usr/local/bin traefik && \
    rm /tmp/traefik.tar.gz && \
    chmod +x /usr/local/bin/traefik && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy Traefik configuration file
COPY traefik.yml traefik.yml
COPY .traefik/ .traefik/

# Copy Procfile
COPY Procfile Procfile

# Install Hivemind
RUN curl -L https://github.com/DarthSim/hivemind/releases/download/v1.1.0/hivemind-v1.1.0-linux-amd64.gz -o hivemind.gz
RUN gunzip hivemind.gz
RUN mv hivemind /usr/local/bin/hivemind
RUN chmod +x /usr/local/bin/hivemind

# Copy built artifacts: gems, application
COPY --from=build-rails /usr/local/bundle /usr/local/bundle
COPY --from=build-rails /app /app

# Build openssl1.1.1 from the source
# RUN mkdir $HOME/opt && cd $HOME/opt && wget https://www.openssl.org/source/openssl-1.1.1o.tar.gz && tar -zxvf openssl-1.1.1o.tar.gz && \
#   cd openssl-1.1.1o && ./config && make && mkdir $HOME/opt/lib && \
#   mv $HOME/opt/openssl-1.1.1o/libcrypto.so.1.1 $HOME/opt/lib/ && \
#   mv $HOME/opt/openssl-1.1.1o/libssl.so.1.1 $HOME/opt/lib/
# ENV LD_LIBRARY_PATH=$HOME/opt/lib:$LD_LIBRARY_PATH
RUN cd tmp/ && wget http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb && \
  dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# Run and own only the runtime files as a non-root user for security
RUN useradd app --create-home --shell /bin/bash && \
    chown -R app:app db log tmp
USER app:app

# Only copy the final release from the build stage
COPY --from=phx-builder --chown=app:app /app/_build/${MIX_ENV}/rel/tuist_cloud ./phx
COPY --from=phx-builder --chown=app:app /app/priv/secrets/secrets.yml.enc ./phx/priv/secrets/secrets.yml.enc
# COPY --from=phx-builder --chown=app:app /app/deps/castore/priv/cacerts.pem ./deps/castore/priv/cacerts.pem

# Entrypoint prepares the database.
ENTRYPOINT ["/app/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["/usr/local/bin/hivemind", "Procfile"]

ENV DATABASE_CA_CERT_FILEPATH "/app/phx/deps/castore/priv/cacerts.pem"
ENV ECTO_IPV6 false
ENV ERL_AFLAGS "-proto_dist inet6_tcp"
