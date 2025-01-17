# We use the Alpine variant for its small size while still having everything we need
FROM elixir:1.15.6-alpine

# Install build dependencies
RUN apk add --no-cache build-base

# Create a directory for our application
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# Copy our mix files first
# This is a performance optimization - Docker will cache our dependencies
# unless mix.exs or mix.lock change
COPY mix.exs mix.lock ./

# Get all our Elixir dependencies
RUN mix deps.get

# Copy over all the rest of our application files
COPY . .

# Compile the application
RUN mix do compile

# Set our environment to production
ENV MIX_ENV=prod

# The command that starts our application
CMD ["mix", "run", "--no-halt"]
