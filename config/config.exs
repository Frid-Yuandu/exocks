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
  server_address: {127, 0, 0, 1},
  server_port: 6716

config :server,
  local_address: {127, 0, 0, 1},
  local_port: 6716,
  passwords: %{"user" => "pass"}

config :logger,
  backends: [
    :console,
    {LoggerFileBackend, :client_log},
    {LoggerFileBackend, :server_log},
    {LoggerFileBackend, :client_error},
    {LoggerFileBackend, :server_error}
  ]

config :logger, :console,
  level: :debug,
  format: "$time [$level] $message\n"

config :logger, :client_log,
  path: "log/client/client.log",
  level: :debug,
  format: "$date-$time [$level] $message\n\t$metadata\n",
  metadata: [:line, :mfa, :pid],
  metadata_filter: [application: :client],
  rotate: %{max_bytes: 102_400, keep: 2}

config :logger, :server_log,
  path: "log/server/server.log",
  level: :debug,
  format: "$date-$time [$level] $message\n\t$metadata\n",
  metadata: [:line, :mfa, :pid],
  metadata_filter: [application: :server],
  rotate: %{max_bytes: 102_400, keep: 2}

config :logger, :client_error,
  path: "log/client/error.log",
  level: :error,
  format: "$date-$time [$level] $message\n\t$metadata\n",
  metadata: [:line, :mfa, :pid],
  metadata_filter: [application: :client],
  rotate: %{max_bytes: 102_400, keep: 2}

config :logger, :server_error,
  path: "log/server/error.log",
  level: :error,
  format: "$date-$time [$level] $message\n\t$metadata\n",
  metadata: [:line, :mfa, :pid],
  metadata_filter: [application: :server],
  rotate: %{max_bytes: 102_400, keep: 2}
