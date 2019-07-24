defmodule ElKube.Repo do
  use Ecto.Repo,
    otp_app: :el_kube,
    adapter: Ecto.Adapters.Postgres
end
