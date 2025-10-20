defmodule AshSqlDeb.Repo do
  use Ecto.Repo,
    otp_app: :ash_sql_deb,
    adapter: Ecto.Adapters.Postgres
end
