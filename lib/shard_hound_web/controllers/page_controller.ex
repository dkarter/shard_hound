defmodule ShardHoundWeb.PageController do
  use ShardHoundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
