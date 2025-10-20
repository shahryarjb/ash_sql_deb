defmodule AshSqlDebWeb.PageController do
  use AshSqlDebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
