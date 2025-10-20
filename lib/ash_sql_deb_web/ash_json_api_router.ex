defmodule AshSqlDebWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [AshSqlDeb.MishkaBlog],
    open_api: "/open_api"
end
