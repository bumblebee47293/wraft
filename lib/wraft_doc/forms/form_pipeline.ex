defmodule WraftDoc.Forms.FormPipeline do
  @moduledoc """
  form mapping  model.
  """
  alias __MODULE__
  use WraftDoc.Schema

  @fields [:form_id, :pipeline_id]

  schema "form_pipeline" do
    belongs_to(:form, WraftDoc.Forms.Form)
    belongs_to(:pipeline, WraftDoc.Document.Pipeline)

    timestamps()
  end

  def changeset(%FormPipeline{} = form_pipeline, params \\ %{}) do
    form_pipeline
    |> cast(params, @fields)
    |> validate_required(@fields)
    |> foreign_key_constraint(:form_id, message: "Please enter an existing form")
    |> foreign_key_constraint(:pipeline_id, message: "Please enter an existing pipeline")
    |> unique_constraint(@fields, name: :form_pipeline_unique_index, message: "already exist")
  end
end
