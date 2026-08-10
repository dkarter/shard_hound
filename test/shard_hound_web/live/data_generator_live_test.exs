defmodule ShardHoundWeb.DataGeneratorLiveTest do
  use ShardHoundWeb.ConnCase, async: false
  use Oban.Testing, repo: ShardHound.Repo

  import Phoenix.LiveViewTest

  alias ShardHound.DemoData.GenerateDatasetWorker

  test "renders the generation form and updates its values", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#data-generator")
    assert has_element?(view, "#data-generator-form")
    assert has_element?(view, "#generate-data-button")

    view
    |> form("#data-generator-form", %{
      "generation_params" => %{
        "organizations" => "2",
        "devices_per_organization" => "10"
      }
    })
    |> render_change()

    assert has_element?(view, "#generation_params_organizations[value='2']")
  end

  test "queues a generation coordinator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#data-generator-form", %{
      "generation_params" => %{
        "organizations" => "1",
        "devices_per_organization" => "2",
        "software_per_device" => "2",
        "groups_per_organization" => "1",
        "custom_packages_per_organization" => "1",
        "deployments_per_organization" => "1",
        "managed_packages" => "2"
      }
    })
    |> render_submit()

    assert has_element?(view, "#generation-status")
    assert_enqueued(worker: GenerateDatasetWorker, args: %{organizations: 1})
  end
end
