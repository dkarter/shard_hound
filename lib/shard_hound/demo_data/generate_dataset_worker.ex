defmodule ShardHound.DemoData.GenerateDatasetWorker do
  use Oban.Worker,
    queue: :data_generation,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:generation_id]]

  alias ShardHound.DemoData.GenerateOrganizationWorker
  alias ShardHound.DeviceManagement.ShardHoundPackage
  alias ShardHound.Repo

  @packages [
    %{
      name: "Google Chrome",
      slug: "google-chrome",
      publisher: "Google",
      version: "140.0.7339.41"
    },
    %{name: "Mozilla Firefox", slug: "mozilla-firefox", publisher: "Mozilla", version: "142.0"},
    %{
      name: "Visual Studio Code",
      slug: "visual-studio-code",
      publisher: "Microsoft",
      version: "1.103.0"
    },
    %{name: "Slack", slug: "slack", publisher: "Salesforce", version: "4.45.64"},
    %{name: "Zoom Workplace", slug: "zoom", publisher: "Zoom", version: "6.5.7"},
    %{name: "1Password", slug: "1password", publisher: "AgileBits", version: "8.11.6"},
    %{name: "Docker Desktop", slug: "docker-desktop", publisher: "Docker", version: "4.44.3"},
    %{
      name: "Microsoft Teams",
      slug: "microsoft-teams",
      publisher: "Microsoft",
      version: "25206.1207"
    },
    %{name: "Notion", slug: "notion", publisher: "Notion Labs", version: "4.13.0"},
    %{name: "Figma", slug: "figma", publisher: "Figma", version: "125.6.5"}
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    packages = Enum.take(@packages, args["managed_packages"])
    ensure_managed_packages(packages)

    Enum.each(1..args["organizations"], fn organization_index ->
      args
      |> Map.put("organization_index", organization_index)
      |> Map.put("package_definitions", packages)
      |> GenerateOrganizationWorker.new()
      |> Oban.insert!()
    end)

    :ok
  end

  defp ensure_managed_packages(packages) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(packages, fn package ->
        %{
          name: package.name,
          slug: package.slug,
          platform: "universal",
          architecture: "universal",
          installer_type: "managed",
          latest_version: package.version,
          metadata: %{publisher: package.publisher},
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ShardHoundPackage, rows,
      conflict_target: [:slug, :platform, :architecture],
      on_conflict: {:replace, [:name, :latest_version, :metadata, :updated_at]}
    )
  end
end
