defmodule AshSqlDeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshSqlDebWeb.Telemetry,
      AshSqlDeb.Repo,
      {DNSCluster, query: Application.get_env(:ash_sql_deb, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AshSqlDeb.PubSub},
      # Start a worker by calling: AshSqlDeb.Worker.start_link(arg)
      # {AshSqlDeb.Worker, arg},
      # Start to serve requests, typically the last entry
      AshSqlDebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshSqlDeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshSqlDebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
