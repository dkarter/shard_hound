defmodule ShardHound.DemoDataTest do
  use ShardHound.DataCase, async: false
  use Oban.Testing, repo: ShardHound.ObanRepo

  import Ecto.Query

  alias ShardHound.DemoData
  alias ShardHound.DemoData.GenerateDatasetWorker
  alias ShardHound.DemoData.GenerateOrganizationWorker
  alias ShardHound.DeviceManagement.CustomPackage
  alias ShardHound.DeviceManagement.Deployment
  alias ShardHound.DeviceManagement.Device
  alias ShardHound.DeviceManagement.DeviceSoftware
  alias ShardHound.DeviceManagement.Group
  alias ShardHound.DeviceManagement.GroupDevice
  alias ShardHound.DeviceManagement.Organization
  alias ShardHound.DeviceManagement.ShardHoundPackage

  test "validates connected generation counts" do
    changeset =
      DemoData.change_generation(%ShardHound.DemoData.GenerationParams{}, %{
        "managed_packages" => "2",
        "software_per_device" => "3"
      })

    refute changeset.valid?
    assert "cannot exceed managed packages" in errors_on(changeset).software_per_device
  end

  test "workers create a connected organization dataset" do
    generation_id = Ecto.UUID.generate()

    args = %{
      generation_id: generation_id,
      organizations: 1,
      devices_per_organization: 4,
      software_per_device: 2,
      groups_per_organization: 2,
      custom_packages_per_organization: 2,
      deployments_per_organization: 3,
      managed_packages: 3
    }

    assert :ok = perform_job(GenerateDatasetWorker, args)
    assert_enqueued(worker: GenerateOrganizationWorker, args: %{generation_id: generation_id})
    assert ShardHound.DemoData.generation_status(generation_id).active == 1

    organization_job =
      Oban.Job
      |> where([job], job.worker == ^inspect(GenerateOrganizationWorker))
      |> ShardHound.ObanRepo.one!()

    assert :ok = perform_job(GenerateOrganizationWorker, organization_job.args)
    assert :ok = perform_job(GenerateOrganizationWorker, organization_job.args)

    organization = ShardHound.Repo.one!(Organization)

    assert ShardHound.Repo.aggregate(Device, :count) == 4
    assert ShardHound.Repo.aggregate(DeviceSoftware, :count) == 8
    assert ShardHound.Repo.aggregate(Group, :count) == 2
    assert ShardHound.Repo.aggregate(GroupDevice, :count) > 0
    assert ShardHound.Repo.aggregate(CustomPackage, :count) == 2
    assert ShardHound.Repo.aggregate(ShardHoundPackage, :count) == 3
    assert ShardHound.Repo.aggregate(Deployment, :count) == 3

    assert ShardHound.Repo.exists?(
             from software in DeviceSoftware,
               where: software.organization_id == ^organization.id and software.version != ""
           )
  end

  test "tenant foreign keys reject cross-organization device data" do
    organization = ShardHound.Repo.insert!(%Organization{name: "One", slug: "one"})
    other_organization = ShardHound.Repo.insert!(%Organization{name: "Two", slug: "two"})

    device =
      ShardHound.Repo.insert!(%Device{
        organization_id: organization.id,
        serial_number: "ONE-1",
        hostname: "one-1",
        platform: "macos",
        architecture: "arm64",
        os_version: "15.6"
      })

    assert_raise Ecto.ConstraintError, fn ->
      ShardHound.Repo.insert!(%DeviceSoftware{
        organization_id: other_organization.id,
        device_id: device.id,
        name: "Google Chrome",
        version: "140.0",
        bundle_identifier: "com.google.Chrome"
      })
    end
  end
end
