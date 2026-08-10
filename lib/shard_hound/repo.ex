defmodule ShardHound.Repo do
  use Ecto.Repo,
    otp_app: :shard_hound,
    adapter: Ecto.Adapters.Postgres
end
