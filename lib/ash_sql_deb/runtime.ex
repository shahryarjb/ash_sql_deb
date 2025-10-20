defmodule AshSqlDeb.Runtime do
  use Ash.Domain,
    otp_app: :ash_sql_deb

  resources do
    resource AshSqlDeb.Runtime.Site
  end
end
