defmodule WraftDoc.Document do
  @moduledoc """
  Module that handles the repo connections of the document context.
  """
  import Ecto
  import Ecto.Query

  alias WraftDoc.{
    Repo,
    Account.User,
    Document.Layout,
    Document.ContentType,
    Document.Engine,
    Document.Instance,
    Document.Theme,
    Document.DataTemplate,
    Document.Asset,
    Enterprise,
    Enterprise.Flow,
    Enterprise.Flow.State
  }

  @doc """
  Create a layout.
  """
  @spec create_layout(User.t(), Engine.t(), map) :: Layout.t() | {:error, Ecto.Changeset.t()}
  def create_layout(%{organisation_id: org_id} = current_user, engine, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:layouts, engine: engine)
    |> Layout.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, layout} ->
        layout |> slug_file_upload(params)

      changeset = {:error, _} ->
        changeset
    end
  end

  @doc """
  Upload layout slug file.
  """
  @spec slug_file_upload(Layout.t(), map) :: Layout.t() | {:error, Ecto.Changeset.t()}
  def slug_file_upload(layout, %{"slug_file" => _} = params) do
    layout
    |> Layout.file_changeset(params)
    |> Repo.update()
    |> case do
      {:ok, layout} ->
        layout |> Repo.preload([:engine, :creator])

      {:error, _} = changeset ->
        changeset
    end
  end

  def slug_file_upload(layout, _params) do
    layout |> Repo.preload([:engine])
  end

  @doc """
  Create a content type.
  """
  @spec create_content_type(User.t(), Layout.t(), Flow.t(), map) ::
          ContentType.t() | {:error, Ecto.Changeset.t()}
  def create_content_type(%{organisation_id: org_id} = current_user, layout, flow, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:content_types, layout: layout, flow: flow)
    |> ContentType.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, %ContentType{} = content_type} ->
        content_type |> Repo.preload([:layout, :flow])

      changeset = {:error, _} ->
        changeset
    end
  end

  @doc """
  List all engines.
  """
  @spec engines_list() :: list
  def engines_list() do
    Repo.all(Engine)
  end

  @doc """
  List all layouts.
  """
  @spec layout_index(User.t(), map) :: map
  def layout_index(%{organisation_id: org_id}, params) do
    from(l in Layout,
      where: l.organisation_id == ^org_id,
      order_by: [desc: l.id],
      preload: [:engine]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Show a layout.
  """
  @spec show_layout(binary) :: %Layout{engine: Engine.t(), creator: User.t()}
  def show_layout(uuid) do
    get_layout(uuid)
    |> Repo.preload([:engine, :creator])
  end

  @doc """
  Get a layout from its UUID.
  """
  @spec get_layout(binary) :: Layout.t()
  def get_layout(uuid) do
    Repo.get_by(Layout, uuid: uuid)
  end

  @doc """
  Update a layout.
  """
  @spec update_layout(Layout.t(), map) :: %Layout{engine: Engine.t(), creator: User.t()}
  def update_layout(layout, %{"engine_uuid" => engine_uuid} = params) do
    %Engine{id: id} = get_engine(engine_uuid)
    {_, params} = Map.pop(params, "engine_uuid")
    params = params |> Map.merge(%{"engine_id" => id})
    update_layout(layout, params)
  end

  def update_layout(layout, params) do
    layout
    |> Layout.update_changeset(params)
    |> Repo.update()
    |> case do
      {:error, _} = changeset ->
        changeset

      {:ok, layout} ->
        layout |> slug_file_upload(params)
    end
  end

  @doc """
  Delete a layout.
  """
  @spec delete_layout(Layout.t()) :: {:ok, Layout.t()} | {:error, Ecto.Changeset.t()}
  def delete_layout(layout) do
    layout
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :content_types,
      message:
        "Cannot delete the layout. Some Content types depend on this layout. Update those content types and then try again.!"
    )
    |> Repo.delete()
  end

  @doc """
  List all content types.
  """
  @spec content_type_index(User.t(), map) :: map
  def content_type_index(%{organisation_id: org_id}, params) do
    from(ct in ContentType,
      where: ct.organisation_id == ^org_id,
      order_by: [desc: ct.id],
      preload: [:layout, :flow]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Show a content type.
  """
  @spec show_content_type(binary) :: %ContentType{layout: %Layout{}, creator: %User{}}
  def show_content_type(uuid) do
    get_content_type(uuid)
    |> Repo.preload([:layout, :creator, :flow])
  end

  @doc """
  Get a content type from its UUID.
  """
  @spec get_content_type(binary) :: ContentType.t()
  def get_content_type(uuid) do
    Repo.get_by(ContentType, uuid: uuid)
  end

  @doc """
  Update a content type.
  """
  @spec update_content_type(ContentType.t(), map) ::
          %ContentType{
            layout: Layout.t(),
            creator: User.t()
          }
          | {:error, Ecto.Changeset.t()}
  def update_content_type(
        content_type,
        %{"layout_uuid" => layout_uuid, "flow_uuid" => f_uuid} = params
      ) do
    %Layout{id: id} = get_layout(layout_uuid)
    %Flow{id: f_id} = Enterprise.get_flow(f_uuid)
    {_, params} = Map.pop(params, "layout_uuid")
    {_, params} = Map.pop(params, "flow_uuid")
    params = params |> Map.merge(%{"layout_id" => id, "flow_id" => f_id})
    update_content_type(content_type, params)
  end

  def update_content_type(content_type, params) do
    content_type
    |> ContentType.update_changeset(params)
    |> Repo.update()
    |> case do
      {:error, _} = changeset ->
        changeset

      {:ok, content_type} ->
        content_type |> Repo.preload([:layout, :creator, :flow])
    end
  end

  @doc """
  Delete a content type.
  """
  @spec delete_content_type(ContentType.t()) ::
          {:ok, ContentType.t()} | {:error, Ecto.Changeset.t()}
  def delete_content_type(content_type) do
    content_type
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :instances,
      message:
        "Cannot delete the content type. There are many contents under this content type. Delete those contents and try again.!"
    )
    |> Repo.delete()
  end

  @doc """
  Create a new instance.
  """
  @spec create_instance(User.t(), ContentType.t(), State.t(), map) ::
          %Instance{content_type: ContentType.t(), state: State.t()}
          | {:error, Ecto.Changeset.t()}
  def create_instance(current_user, %{id: c_id, prefix: prefix} = c_type, state, params) do
    instance_id = c_id |> create_instance_id(prefix)
    params = params |> Map.merge(%{"instance_id" => instance_id})

    c_type
    |> build_assoc(:instances, state: state, creator: current_user)
    |> Instance.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, content} ->
        content |> Repo.preload([:content_type, :state])

      changeset = {:error, _} ->
        changeset
    end
  end

  # Create Instance ID from the prefix of the content type
  @spec create_instance_id(integer, binary) :: binary
  defp create_instance_id(c_id, prefix) do
    instance_count =
      from(i in Instance, where: i.content_type_id == ^c_id, select: count(i.id))
      |> Repo.one()
      |> add(1)
      |> to_string
      |> String.pad_leading(4, "0")

    prefix <> instance_count
  end

  # Add two integers
  @spec add(integer, integer) :: integer
  defp add(num1, num2) do
    num1 + num2
  end

  @doc """
  List all instances under an organisation.
  """
  @spec instance_index_of_an_organisation(User.t(), map) :: map
  def instance_index_of_an_organisation(%{organisation_id: org_id}, params) do
    from(i in Instance,
      join: u in User,
      where: u.organisation_id == ^org_id and i.creator_id == u.id,
      order_by: [desc: i.id],
      preload: [:content_type, :state]
    )
    |> Repo.paginate(params)
  end

  @doc """
  List all instances under a content types.
  """
  @spec instance_index(binary, map) :: map
  def instance_index(c_type_uuid, params) do
    from(i in Instance,
      join: ct in ContentType,
      where: ct.uuid == ^c_type_uuid and i.content_type_id == ct.id,
      order_by: [desc: i.id],
      preload: [:content_type, :state]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Get an instance from its UUID.
  """
  @spec get_instance(binary) :: Instance.t()
  def get_instance(uuid) do
    Repo.get_by(Instance, uuid: uuid)
  end

  @doc """
  Show an instance.
  """
  @spec show_instance(binary) ::
          %Instance{creator: User.t(), content_type: ContentType.t(), state: State.t()} | nil
  def show_instance(instance_uuid) do
    instance_uuid |> get_instance() |> Repo.preload([:creator, :content_type, :state])
  end

  @doc """
  Update an instance.
  """
  @spec update_instance(Instance.t(), map) ::
          %Instance{content_type: ContentType.t(), state: State.t(), creator: Creator.t()}
          | {:error, Ecto.Changeset.t()}

  def update_instance(instance, %{"state_uuid" => state_uuid} = params) do
    %State{id: id} = Enterprise.get_state(state_uuid)
    {_, params} = Map.pop(params, "state_uuid")
    params = params |> Map.merge(%{"state_id" => id})
    update_instance(instance, params)
  end

  def update_instance(instance, params) do
    instance
    |> Instance.update_changeset(params)
    |> Repo.update()
    |> case do
      {:ok, instance} ->
        instance |> Repo.preload([:creator, :content_type, :state])

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Delete an instance.
  """
  @spec delete_instance(Instance.t()) ::
          {:ok, Instance.t()} | {:error, Ecto.Changeset.t()}
  def delete_instance(instance) do
    instance
    |> Repo.delete()
  end

  @doc """
  Get an engine from its UUID.
  """
  @spec get_engine(binary) :: Engine.t() | nil
  def get_engine(engine_uuid) do
    Repo.get_by(Engine, uuid: engine_uuid)
  end

  @doc """
  Create a theme.
  """
  @spec create_theme(User.t(), map) :: {:ok, Theme.t()} | {:error, Ecto.Changeset.t()}
  def create_theme(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:themes)
    |> Theme.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, theme} ->
        theme |> theme_file_upload(params)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Upload theme file.
  """
  @spec theme_file_upload(Theme.t(), map) :: {:ok, %Theme{}} | {:error, Ecto.Changeset.t()}
  def theme_file_upload(theme, %{"file" => _} = params) do
    theme |> Theme.file_changeset(params) |> Repo.update()
  end

  def theme_file_upload(theme, _params) do
    {:ok, theme}
  end

  @doc """
  Index of themes inside current user's organisation.
  """
  @spec theme_index(User.t(), map) :: map
  def theme_index(%User{organisation_id: org_id}, params) do
    from(t in Theme, where: t.organisation_id == ^org_id, order_by: [desc: t.id])
    |> Repo.paginate(params)
  end

  @doc """
  Get a theme from its UUID.
  """
  @spec get_theme(binary) :: Theme.t() | nil
  def get_theme(theme_uuid) do
    Repo.get_by(Theme, uuid: theme_uuid)
  end

  @doc """
  Show a theme.
  """
  @spec show_theme(binary) :: %Theme{creator: User.t()} | nil
  def show_theme(theme_uuid) do
    theme_uuid |> get_theme() |> Repo.preload([:creator])
  end

  @doc """
  Update a theme.
  """
  @spec update_theme(Theme.t(), map) :: {:ok, Theme.t()} | {:error, Ecto.Changeset.t()}
  def update_theme(theme, params) do
    theme |> Theme.update_changeset(params) |> Repo.update()
  end

  @doc """
  Delete a theme.
  """
  @spec delete_theme(Theme.t()) :: {:ok, Theme.t()}
  def delete_theme(theme) do
    theme
    |> Repo.delete()
  end

  @doc """
  Create a data template.
  """
  @spec create_data_template(User.t(), ContentType.t(), map) ::
          {:ok, DataTemplate.t()} | {:error, Ecto.Changeset.t()}
  def create_data_template(current_user, c_type, params) do
    current_user
    |> build_assoc(:data_templates, content_type: c_type)
    |> DataTemplate.changeset(params)
    |> Repo.insert()
  end

  @doc """
  List all data templates under a content types.
  """
  @spec data_template_index(binary) :: list
  def data_template_index(c_type_uuid) do
    from(dt in DataTemplate,
      join: ct in ContentType,
      where: ct.uuid == ^c_type_uuid and dt.content_type_id == ct.id
    )
    |> Repo.all()
  end

  @doc """
  List all data templates under current user's organisation.
  """
  @spec data_templates_index_of_an_organisation(User.t()) :: list
  def data_templates_index_of_an_organisation(%{organisation_id: org_id}) do
    from(dt in DataTemplate,
      join: u in User,
      where: u.organisation_id == ^org_id and dt.creator_id == u.id
    )
    |> Repo.all()
  end

  @doc """
  Get a data template from its uuid
  """
  @spec get_d_template(binary) :: DataTemplat.t() | nil
  def get_d_template(d_temp_uuid) do
    Repo.get_by(DataTemplate, uuid: d_temp_uuid)
  end

  @doc """
  Show a data template.
  """
  @spec show_d_template(binary) ::
          %DataTemplate{creator: User.t(), content_type: ContentType.t()} | nil
  def show_d_template(d_temp_uuid) do
    d_temp_uuid |> get_d_template() |> Repo.preload([:creator, :content_type])
  end

  @doc """
  Update a data template
  """
  @spec update_data_template(DataTemplate.t(), map) ::
          %DataTemplate{creator: User.t(), content_type: ContentType.t()}
          | {:error, Ecto.Changeset.t()}
  def update_data_template(d_temp, params) do
    d_temp
    |> DataTemplate.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, d_temp} ->
        d_temp |> Repo.preload([:creator, :content_type])

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Delete a data template
  """
  @spec delete_data_template(DataTemplate.t()) :: {:ok, DataTemplate.t()}
  def delete_data_template(d_temp) do
    d_temp |> Repo.delete()
  end

  @doc """
  Create an asset.
  """
  @spec create_asset(User.t(), map) :: {:ok, Asset.t()}
  def create_asset(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})
    current_user |> build_assoc(:assets) |> Asset.changeset(params) |> Repo.insert()
  end

  @doc """
  Index of all assets in an organisation.
  """
  @spec asset_index(integer) :: list
  def asset_index(organisation_id) do
    from(a in Asset, where: a.organisation_id == ^organisation_id) |> Repo.all()
  end

  @doc """
  Show an asset.
  """
  @spec show_asset(binary) :: %Asset{creator: User.t()}
  def show_asset(asset_uuid) do
    asset_uuid
    |> get_asset()
    |> Repo.preload([:creator])
  end

  @doc """
  Get an asset from its UUID.
  """
  @spec get_asset(binary) :: Asset.t()
  def get_asset(uuid) do
    Repo.get_by(Asset, uuid: uuid)
  end

  @doc """
  Update an asset.
  """
  @spec update_asset(Asset.t(), map) :: {:ok, Asset.t()}
  def update_asset(asset, params) do
    asset |> Asset.update_changeset(params) |> Repo.update()
  end

  @doc """
  Delete an asset.
  """
  @spec delete_asset(Asset.t()) :: {:ok, Asset.t()}
  def delete_asset(asset) do
    asset |> Repo.delete()
  end
end
