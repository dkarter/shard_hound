defmodule ShardHound.DemoDataTest do
  use ShardHound.DataCase, async: false
  use Oban.Testing, repo: ShardHound.Repo

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

    organization_job =
      Oban.Job
      |> where([job], job.worker == ^inspect(GenerateOrganizationWorker))
      |> ShardHound.Repo.one!()

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
end
