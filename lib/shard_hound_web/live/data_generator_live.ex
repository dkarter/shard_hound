defmodule ShardHoundWeb.DataGeneratorLive do
  use ShardHoundWeb, :live_view

  alias ShardHound.DemoData
  alias ShardHound.DemoData.GenerationParams

  @impl true
  def mount(_params, _session, socket) do
    params = %GenerationParams{}

    {:ok,
     socket
     |> assign(:page_title, "Dataset Generator")
     |> assign(:generation_id, nil)
     |> assign(:refresh_ref, nil)
     |> assign(:generation_status, DemoData.generation_status(nil))
     |> assign(:database_stats, DemoData.database_stats())
     |> assign(:estimate, estimate(params))
     |> assign(:form, to_form(DemoData.change_generation(params)))}
  end

  @impl true
  def handle_event("validate", %{"generation_params" => params}, socket) do
    changeset =
      %GenerationParams{}
      |> DemoData.change_generation(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:estimate, estimate(Ecto.Changeset.apply_changes(changeset)))
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("generate", %{"generation_params" => params}, socket) do
    case DemoData.enqueue_generation(params) do
      {:ok, generation_id, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Generation queued. Oban is distributing organization jobs.")
         |> cancel_refresh()
         |> assign(:generation_id, generation_id)
         |> assign(:generation_status, DemoData.generation_status(generation_id))
         |> schedule_refresh()}

      {:error, %Ecto.Changeset{data: %GenerationParams{}} = changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The generation job could not be queued.")}
    end
  end

  @impl true
  def handle_info(
        {:refresh_generation, generation_id},
        %{assigns: %{generation_id: generation_id}} = socket
      ) do
    status = DemoData.generation_status(generation_id)
    socket = assign(socket, :refresh_ref, nil)

    socket =
      if status.active > 0 do
        schedule_refresh(socket)
      else
        assign(socket, :database_stats, DemoData.database_stats())
      end

    {:noreply, assign(socket, :generation_status, status)}
  end

  def handle_info({:refresh_generation, _stale_generation_id}, socket), do: {:noreply, socket}

  defp schedule_refresh(socket) do
    refresh_ref =
      Process.send_after(self(), {:refresh_generation, socket.assigns.generation_id}, 1_000)

    assign(socket, :refresh_ref, refresh_ref)
  end

  defp cancel_refresh(%{assigns: %{refresh_ref: nil}} = socket), do: socket

  defp cancel_refresh(socket) do
    Process.cancel_timer(socket.assigns.refresh_ref)
    assign(socket, :refresh_ref, nil)
  end

  defp estimate(params) do
    organizations = params.organizations || 0
    devices = organizations * (params.devices_per_organization || 0)
    software = devices * (params.software_per_device || 0)
    groups = organizations * (params.groups_per_organization || 0)
    custom_packages = organizations * (params.custom_packages_per_organization || 0)
    deployments = organizations * (params.deployments_per_organization || 0)

    %{
      organizations: organizations,
      devices: devices,
      software: software,
      groups: groups,
      custom_packages: custom_packages,
      deployments: deployments,
      total: organizations + devices + software + groups + custom_packages + deployments
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="data-generator" class="space-y-9">
        <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-end">
          <div class="max-w-3xl">
            <div class="mb-5 flex items-center gap-3 text-xs font-semibold uppercase tracking-[0.22em] text-cyan-300">
              <span class="h-px w-8 bg-cyan-300/60"></span> Synthetic fleet foundry
            </div>
            <h1 class="text-balance text-4xl font-semibold tracking-[-0.04em] text-white sm:text-6xl">
              Build a fleet worth <span class="text-cyan-300">sharding.</span>
            </h1>
            <p class="mt-5 max-w-2xl text-pretty text-base leading-7 text-slate-400 sm:text-lg">
              Queue logically connected organizations, devices, software inventory, dynamic groups,
              packages, and deployments. Every tenant row carries the organization shard key.
            </p>
          </div>

          <div class="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-white/8 bg-white/8 shadow-2xl shadow-black/20">
            <.stat value={@database_stats.organizations} label="Organizations" />
            <.stat value={@database_stats.devices} label="Devices" />
            <.stat value={@database_stats.software} label="Software rows" />
            <.stat value={@database_stats.deployments} label="Deployments" />
          </div>
        </div>

        <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_21rem]">
          <div class="overflow-hidden rounded-3xl border border-white/8 bg-[#0c1220]/95 shadow-[0_24px_80px_rgba(0,0,0,0.28)]">
            <div class="flex items-center justify-between border-b border-white/8 px-6 py-5 sm:px-8">
              <div>
                <h2 class="text-lg font-semibold text-white">Generation profile</h2>
                <p class="mt-1 text-sm text-slate-500">
                  One coordinator job, then one job per organization.
                </p>
              </div>
              <span class="hidden rounded-full border border-violet-300/20 bg-violet-300/10 px-3 py-1 text-xs font-semibold text-violet-200 sm:block">
                shard key: organization_id
              </span>
            </div>

            <.form
              for={@form}
              id="data-generator-form"
              phx-change="validate"
              phx-submit="generate"
              class="p-6 sm:p-8"
            >
              <div class="grid gap-x-5 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
                <%= for field <- GenerationParams.count_fields() do %>
                  <.input
                    field={@form[field.name]}
                    type="number"
                    label={field.label}
                    min={field.min}
                    max={field.max}
                    class={[
                      "w-full rounded-xl border border-white/10 bg-[#070b14] px-4 py-3 text-sm font-medium text-white outline-none transition placeholder:text-slate-700 focus:border-cyan-300/60 focus:ring-4 focus:ring-cyan-300/5"
                    ]}
                    error_class={[
                      "w-full rounded-xl border border-rose-400/60 bg-rose-400/5 px-4 py-3 text-sm font-medium text-white outline-none ring-4 ring-rose-400/5"
                    ]}
                  />
                <% end %>
              </div>

              <div class="mt-7 flex flex-col gap-5 border-t border-white/8 pt-6 sm:flex-row sm:items-center sm:justify-between">
                <div class="flex items-center gap-3 text-sm text-slate-400">
                  <span class="grid size-9 place-items-center rounded-xl bg-cyan-300/10 text-cyan-300">
                    <.icon name="hero-circle-stack" class="size-5" />
                  </span>
                  <span>
                    Estimated
                    <strong class="font-semibold text-white">{format_number(@estimate.total)}</strong>
                    primary rows
                  </span>
                </div>
                <.button
                  id="generate-data-button"
                  type="submit"
                  phx-disable-with="Queueing jobs..."
                  class="group inline-flex min-h-12 items-center justify-center gap-2 rounded-xl bg-cyan-300 px-6 text-sm font-bold text-slate-950 shadow-[0_12px_36px_rgba(34,211,238,0.16)] transition hover:-translate-y-0.5 hover:bg-cyan-200 hover:shadow-[0_16px_44px_rgba(34,211,238,0.25)] active:translate-y-0 disabled:cursor-wait disabled:opacity-70"
                >
                  Queue generation
                  <.icon
                    name="hero-arrow-right"
                    class="size-4 transition group-hover:translate-x-0.5"
                  />
                </.button>
              </div>
            </.form>
          </div>

          <aside class="space-y-6">
            <div class="rounded-3xl border border-white/8 bg-[#0c1220]/95 p-6">
              <div class="flex items-center justify-between">
                <h2 class="text-sm font-semibold uppercase tracking-[0.16em] text-slate-400">
                  Row forecast
                </h2>
                <span class="size-2 rounded-full bg-cyan-300 shadow-[0_0_12px_rgba(34,211,238,0.7)]"></span>
              </div>
              <dl class="mt-5 space-y-3 text-sm">
                <.forecast label="Devices" value={@estimate.devices} />
                <.forecast label="Software" value={@estimate.software} />
                <.forecast label="Dynamic groups" value={@estimate.groups} />
                <.forecast label="Custom packages" value={@estimate.custom_packages} />
                <.forecast label="Deployments" value={@estimate.deployments} border />
              </dl>
            </div>

            <div
              :if={@generation_id}
              id="generation-status"
              class="rounded-3xl border border-emerald-300/15 bg-emerald-300/[0.04] p-6"
            >
              <div class="flex items-center gap-3">
                <span class="relative flex size-3">
                  <span
                    :if={@generation_status.active > 0}
                    class="absolute inline-flex size-full animate-ping rounded-full bg-emerald-400 opacity-60"
                  ></span>
                  <span class="relative inline-flex size-3 rounded-full bg-emerald-400"></span>
                </span>
                <h2 class="text-sm font-semibold text-emerald-100">
                  {if(@generation_status.active > 0,
                    do: "Generation active",
                    else: "Generation settled"
                  )}
                </h2>
              </div>
              <div class="mt-5 grid grid-cols-3 gap-2 text-center">
                <.job_count label="Active" value={@generation_status.active} />
                <.job_count label="Done" value={@generation_status.completed} />
                <.job_count label="Failed" value={@generation_status.failed} />
              </div>
              <p class="mt-4 truncate font-mono text-[10px] text-slate-600" title={@generation_id}>
                {@generation_id}
              </p>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp stat(assigns) do
    ~H"""
    <div class="bg-[#0c1220] p-4">
      <div class="text-2xl font-semibold tabular-nums text-white">{format_number(@value)}</div>
      <div class="mt-1 text-xs uppercase tracking-wider text-slate-500">{@label}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :border, :boolean, default: false

  defp forecast(assigns) do
    ~H"""
    <div class={["flex justify-between", @border && "border-t border-white/8 pt-3"]}>
      <dt class="text-slate-500">{@label}</dt>
      <dd class="font-medium tabular-nums text-slate-200">{format_number(@value)}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp job_count(assigns) do
    ~H"""
    <div class="rounded-xl bg-black/15 px-2 py-3">
      <div class="text-lg font-semibold tabular-nums text-white">{@value}</div>
      <div class="text-[10px] uppercase tracking-wider text-slate-500">{@label}</div>
    </div>
    """
  end

  defp format_number(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
