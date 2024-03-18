# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :client,
  local_port: 8899,
  remote_address: {127, 0, 0, 1},
  remote_port: 6716

config :server,
  local_port: 6716

config :logger,
  backends: [
    :console,
    {LoggerFileBackend, :client_log},
    {LoggerFileBackend, :server_log}
  ]

config :logger, :console,
  level: :debug,
  format: "$time [$level] $message\n"

config :logger, :client_log,
  path: "client.log",
  level: :debug,
  format: "$time [$level] $message\n\t$metadata\n",
  metadata: :all,
  metadata_filter: [application: :client]

config :logger, :server_log,
  path: "server.log",
  level: :debug,
  format: "$time [$level] $message\n\t$metadata\n",
  metadata: :all,
  metadata_filter: [application: :server]
