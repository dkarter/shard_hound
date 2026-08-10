defmodule ShardHound.DemoData.GenerateOrganizationWorker do
  use Oban.Worker,
    queue: :data_generation,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:generation_id, :organization_index]
    ]

  import Ecto.Query

  alias ShardHound.DeviceManagement.CustomPackage
  alias ShardHound.DeviceManagement.Deployment
  alias ShardHound.DeviceManagement.Device
  alias ShardHound.DeviceManagement.DeviceSoftware
  alias ShardHound.DeviceManagement.Group
  alias ShardHound.DeviceManagement.GroupDevice
  alias ShardHound.DeviceManagement.Organization
  alias ShardHound.DeviceManagement.ShardHoundPackage
  alias ShardHound.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Repo.transaction(fn -> generate_organization(args) end, timeout: :infinity) do
      {:ok, _organization} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_organization(args) do
    now = DateTime.utc_now(:second)
    generation_key = String.slice(args["generation_id"], 0, 8)
    organization_index = args["organization_index"]

    organization =
      %Organization{
        name: "Demo Organization #{generation_key}-#{organization_index}",
        slug: "demo-#{generation_key}-#{organization_index}"
      }
      |> Repo.insert!()

    devices = insert_devices(organization.id, args, now)
    memberships = insert_software(organization.id, devices, args, now)
    groups = insert_groups(organization.id, memberships, args, now)
    custom_packages = insert_custom_packages(organization.id, args, now)
    insert_deployments(organization.id, groups, custom_packages, args, now)

    organization
  end

  defp insert_devices(organization_id, args, now) do
    generation_key = String.slice(args["generation_id"], 0, 8)
    organization_index = args["organization_index"]

    rows =
      Enum.map(1..args["devices_per_organization"], fn device_index ->
        platform = if rem(device_index, 3) == 0, do: "windows", else: "macos"

        %{
          organization_id: organization_id,
          serial_number: "#{generation_key}-#{organization_index}-#{device_index}",
          hostname: "device-#{organization_index}-#{device_index}",
          platform: platform,
          architecture: if(platform == "macos", do: "arm64", else: "x86_64"),
          os_version: if(platform == "macos", do: "15.6", else: "11-24H2"),
          last_seen_at: DateTime.add(now, -rem(device_index, 168), :hour),
          metadata: %{office: "site-#{rem(device_index, 12) + 1}"},
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, devices} = Repo.insert_all(Device, rows, returning: [:id, :serial_number])
    devices
  end

  defp insert_software(organization_id, devices, args, now) do
    definitions = args["package_definitions"]

    {software_rows, memberships} =
      devices
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{}}, fn {device, device_index}, {rows, memberships} ->
        definitions
        |> rotate(device_index - 1)
        |> Enum.take(args["software_per_device"])
        |> Enum.with_index()
        |> Enum.reduce({rows, memberships}, fn {software, software_index}, {rows, memberships} ->
          latest? = rem(device_index + software_index, 4) != 0

          version =
            if latest?, do: software["version"], else: previous_version(software["version"])

          row = %{
            organization_id: organization_id,
            device_id: device.id,
            name: software["name"],
            publisher: software["publisher"],
            version: version,
            bundle_identifier: "com.demo.#{software["slug"]}",
            installed_at:
              DateTime.add(now, -rem(device_index * (software_index + 1), 720), :hour),
            metadata: %{managed: rem(software_index, 2) == 0},
            inserted_at: now,
            updated_at: now
          }

          memberships =
            if latest? do
              Map.update(memberships, software["slug"], [device.id], &[device.id | &1])
            else
              memberships
            end

          {[row | rows], memberships}
        end)
      end)

    software_rows
    |> Enum.chunk_every(1_000)
    |> Enum.each(&Repo.insert_all(DeviceSoftware, &1))

    memberships
  end

  defp insert_groups(organization_id, memberships, args, now) do
    definitions = args["package_definitions"]

    Enum.map(1..args["groups_per_organization"], fn group_index ->
      software = Enum.at(definitions, rem(group_index - 1, length(definitions)))

      group =
        %Group{
          organization_id: organization_id,
          name: "Latest #{software["name"]} #{group_index}",
          description: "Devices reporting the current managed version of #{software["name"]}",
          filter: %{
            "field" => "device_software.version",
            "software_slug" => software["slug"],
            "operator" => "equals_latest"
          },
          refreshed_at: now
        }
        |> Repo.insert!()

      memberships
      |> Map.get(software["slug"], [])
      |> Enum.map(fn device_id ->
        %{
          organization_id: organization_id,
          group_id: group.id,
          device_id: device_id,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> Enum.chunk_every(1_000)
      |> Enum.each(&Repo.insert_all(GroupDevice, &1))

      group
    end)
  end

  defp insert_custom_packages(organization_id, args, now) do
    rows =
      count_range(args["custom_packages_per_organization"])
      |> Enum.map(fn package_index ->
        %{
          organization_id: organization_id,
          name: "Internal Tool #{package_index}",
          slug: "internal-tool-#{package_index}",
          platform: if(rem(package_index, 2) == 0, do: "windows", else: "macos"),
          architecture: "universal",
          installer_type: "custom",
          latest_version: "#{rem(package_index, 4) + 1}.#{package_index}.0",
          metadata: %{owner: "IT Engineering"},
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, packages} =
      Repo.insert_all(CustomPackage, rows, returning: [:id, :name, :latest_version])

    packages
  end

  defp insert_deployments(organization_id, groups, custom_packages, args, now) do
    managed_packages =
      ShardHoundPackage
      |> where([package], package.slug in ^Enum.map(args["package_definitions"], & &1["slug"]))
      |> Repo.all()

    rows =
      count_range(args["deployments_per_organization"])
      |> Enum.map(fn deployment_index ->
        {package_type, package} =
          deployment_package(deployment_index, managed_packages, custom_packages)

        group = Enum.at(groups, rem(deployment_index - 1, length(groups)))

        %{
          organization_id: organization_id,
          group_id: group.id,
          package_id: package.id,
          package_type: package_type,
          name: "Deploy #{package.name} to #{group.name}",
          target_version: package.latest_version,
          status: Enum.at(~w(pending scheduled running completed), rem(deployment_index, 4)),
          scheduled_at: DateTime.add(now, deployment_index, :hour),
          metadata: %{created_by: "demo generator"},
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Deployment, rows)
  end

  defp deployment_package(index, managed_packages, custom_packages)

  defp deployment_package(index, managed_packages, []) do
    {"shard_hound", Enum.at(managed_packages, rem(index - 1, length(managed_packages)))}
  end

  defp deployment_package(index, _managed_packages, custom_packages) when rem(index, 2) == 0 do
    {"custom", Enum.at(custom_packages, rem(index - 1, length(custom_packages)))}
  end

  defp deployment_package(index, managed_packages, _custom_packages) do
    {"shard_hound", Enum.at(managed_packages, rem(index - 1, length(managed_packages)))}
  end

  defp rotate(items, offset) do
    {left, right} = Enum.split(items, rem(offset, length(items)))
    right ++ left
  end

  defp previous_version(version), do: version <> "-old"
  defp count_range(0), do: []
  defp count_range(count), do: 1..count
end
