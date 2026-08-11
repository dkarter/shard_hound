defmodule ShardHound.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShardHoundWeb.Telemetry,
      ShardHound.Repo,
      ShardHound.ObanRepo,
      {Oban, Application.fetch_env!(:shard_hound, Oban)},
      {DNSCluster, query: Application.get_env(:shard_hound, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShardHound.PubSub},
      # Start a worker by calling: ShardHound.Worker.start_link(arg)
      # {ShardHound.Worker, arg},
      # Start to serve requests, typically the last entry
      ShardHoundWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShardHound.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShardHoundWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
