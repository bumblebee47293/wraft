defmodule WraftDocWeb.BlockTemplateControllerTest do
  use WraftDocWeb.ConnCase

  import WraftDoc.Factory
  alias WraftDoc.{Document.BlockTemplate, Repo}

  @valid_attrs %{
    title: "a sample Title",
    body: "a sample Body",
    serialised: "a sample Serialised"
  }

  @invalid_attrs %{}
  setup %{conn: conn} do
    role = insert(:role, name: "admin")
    user = insert(:user, role: role)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(
        Routes.v1_user_path(conn, :signin, %{
          email: user.email,
          password: user.password
        })
      )

    conn = assign(conn, :current_user, user)

    {:ok, %{conn: conn}}
  end

  test "create block_templates by valid attrrs", %{conn: conn} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    count_before = BlockTemplate |> Repo.all() |> length()

    conn =
      post(conn, Routes.v1_block_template_path(conn, :create, @valid_attrs))
      |> doc(operation_id: "create_resource")

    assert count_before + 1 == BlockTemplate |> Repo.all() |> length()
    assert json_response(conn, 200)["title"] == @valid_attrs.title
  end

  test "does not create block_templates by invalid attrs", %{conn: conn} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    count_before = BlockTemplate |> Repo.all() |> length()

    conn =
      post(conn, Routes.v1_block_template_path(conn, :create, @invalid_attrs))
      |> doc(operation_id: "create_resource")

    assert json_response(conn, 422)["errors"]["title"] == ["can't be blank"]
    assert count_before == BlockTemplate |> Repo.all() |> length()
  end

  test "update block_templates on valid attributes", %{conn: conn} do
    user = conn.assigns.current_user
    block_template = insert(:block_template, creator: user)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    count_before = BlockTemplate |> Repo.all() |> length()

    conn =
      put(conn, Routes.v1_block_template_path(conn, :update, block_template.uuid, @valid_attrs))
      |> doc(operation_id: "update_resource")

    assert json_response(conn, 200)["title"] == @valid_attrs.title
    assert count_before == BlockTemplate |> Repo.all() |> length()
  end

  test "does't update block_templates for invalid attrs", %{conn: conn} do
    block_template = insert(:block_template)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    conn =
      put(conn, Routes.v1_block_template_path(conn, :update, block_template.uuid, @invalid_attrs))
      |> doc(operation_id: "update_resource")

    assert json_response(conn, 422)["errors"]["creator_id"] == ["can't be blank"]
  end

  test "index lists assests by current user", %{conn: conn} do
    user = conn.assigns.current_user

    a1 = insert(:block_template)
    a2 = insert(:block_template)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, user)

    conn = get(conn, Routes.v1_block_template_path(conn, :index))
    block_template_index = json_response(conn, 200)["block_templates"]
    block_templates = Enum.map(block_template_index, fn %{"title" => title} -> title end)
    assert List.to_string(block_templates) =~ a1.title
    assert List.to_string(block_templates) =~ a2.title
  end

  test "show renders block_template details by id", %{conn: conn} do
    block_template = insert(:block_template)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    conn = get(conn, Routes.v1_block_template_path(conn, :show, block_template.uuid))

    assert json_response(conn, 200)["title"] == block_template.title
  end

  test "error not found for id does not exists", %{conn: conn} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    conn = get(conn, Routes.v1_block_template_path(conn, :show, Ecto.UUID.generate()))
    assert json_response(conn, 404) == "Not Found"
  end

  test "delete block_template by given id", %{conn: conn} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{conn.assigns.token}")
      |> assign(:current_user, conn.assigns.current_user)

    block_template = insert(:block_template)
    count_before = BlockTemplate |> Repo.all() |> length()

    conn = delete(conn, Routes.v1_block_template_path(conn, :delete, block_template.uuid))
    assert count_before - 1 == BlockTemplate |> Repo.all() |> length()
    assert json_response(conn, 200)["title"] == block_template.title
  end
end
