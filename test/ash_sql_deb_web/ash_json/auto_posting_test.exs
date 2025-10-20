defmodule AshSqlDebWeb.Api.Json.MishkaBlog.AutoPostingTest do
  use AshSqlDebWeb.ConnCase

  require Ash.Query

  @api_tenant_path "/api/json/v1/tenant/admin/mishka-blog/auto-posting"

  test "tenant admin can unarchive their own site's auto posting" do
    {:ok, site} =
      Ash.create(
        AshSqlDeb.Runtime.Site,
        %{
          name: "localhost",
          host: "localhost",
          priority: 100,
          active: true,
          master: true,
          mode: "hybrid",
          frontend_domain: nil,
          allowed_origins: [
            "http://user.example.com:3000",
            "http://app.example.com:3000"
          ]
        },
        authorize?: false
      )

    {:ok, auto_posting} =
      Ash.create(
        AshSqlDeb.MishkaBlog.AutoPosting,
        %{
          name: "test",
          plugin: "test_plugin_one",
          description: "Test auto posting description",
          is_active: false,
          config: %{}
        },
        tenant: site.id,
        authorize?: false
      )


    # Archive it first
    auto_posting
    |> Ash.Changeset.for_destroy(:destroy, %{}, tenant: site.id, authorize?: false)
    |> Ash.destroy!()

    # Unarchive it
    response =
      make_api_request(
        "#{@api_tenant_path}/#{auto_posting.id}/unarchive",
        %{
          "type" => "auto_posting",
          "attributes" => %{}
        },
        method: :patch,
        headers: [{"x-ash-tenant", site.id}]
      )

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["data"]["id"] == auto_posting.id
  end

  # Helpers
  def make_api_request(path, data, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    host = Keyword.get(opts, :host, "localhost")
    method = Keyword.get(opts, :method, "POST")

    [base_path, query_string] =
      case String.split(path, "?", parts: 2) do
        [p, q] -> [p, q]
        [p] -> [p, ""]
      end

    path_info = base_path |> String.trim_leading("/") |> String.split("/")

    # Parse query params and convert JSON:API style brackets to nested maps
    query_params =
      if query_string != "" do
        query_string
        |> URI.decode_query()
        |> parse_json_api_params()
      else
        %{}
      end

    conn =
      %Plug.Conn{
        build_conn()
        | host: host,
          method: method,
          request_path: path,
          path_info: path_info,
          query_string: query_string,
          query_params: query_params,
          params: query_params
      }
      |> put_default_headers()
      |> put_custom_headers(headers)
      |> Map.put(:body_params, %{"data" => data})
      |> Map.update!(:params, fn existing ->
        Map.merge(parse_json_api_params(existing), %{"data" => data})
      end)

    # Extract tenant from x-ash-tenant header and set it on the conn
    conn =
      case List.keyfind(headers, "x-ash-tenant", 0) do
        {"x-ash-tenant", tenant} -> Ash.PlugHelpers.set_tenant(conn, tenant)
        _ -> conn
      end

    AshSqlDebWeb.Endpoint.call(conn, [])
  end

  defp put_default_headers(conn) do
    conn
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("accept", "application/vnd.api+json")
  end

  defp put_custom_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, acc ->
      put_req_header(acc, key, value)
    end)
  end

  # Parse JSON:API style params like page[limit]=2 into nested structure page: %{limit: "2"}
  defp parse_json_api_params(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      # Handle nested brackets like included_page[posts][limit]
      cond do
        # Match: parent[child1][child2] (two levels deep)
        match = Regex.run(~r/^(\w+)\[(\w+)\]\[(\w+)\]$/, key) ->
          [_, parent, child1, child2] = match
          Map.update(acc, parent, %{child1 => %{child2 => value}}, fn existing ->
            Map.update(existing, child1, %{child2 => value}, fn nested ->
              Map.put(nested, child2, value)
            end)
          end)

        # Match: parent[child] (one level deep)
        match = Regex.run(~r/^(\w+)\[(\w+)\]$/, key) ->
          [_, parent, child] = match
          Map.update(acc, parent, %{child => value}, fn existing ->
            Map.put(existing, child, value)
          end)

        # No brackets - just a regular key
        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp parse_json_api_params(_), do: %{}
end
