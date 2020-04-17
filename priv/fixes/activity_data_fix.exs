defmodule ActivityDataFix do
  alias WraftDoc.Repo
  alias Spur.Activity
  import Ecto.Query

  def get_deletion_activity() do
    from(a in Activity,
      where: a.action == "delete",
      select: %{
        id: a.id,
        action: a.action,
        actor: a.actor,
        object: a.object,
        meta: a.meta,
        inserted_at: a.inserted_at
      }
    )
    |> Repo.all()
    |> Task.async_stream(fn x -> update_object(x) end)
    |> Enum.to_list()
  end

  def update_object(%{object: object} = activity) do
    object = object |> String.split(",") |> List.first()
    struct!(Activity, activity) |> Activity.changeset(%{object: object}) |> Repo.update!()
  end
end

ActivityDataFix.get_deletion_activity()
