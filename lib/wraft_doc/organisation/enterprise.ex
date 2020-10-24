defmodule WraftDoc.Enterprise do
  @moduledoc """
  Module that handles the repo connections of the enterprise context.
  """
  import Ecto.Query
  import Ecto
  alias Ecto.Multi

  alias WraftDoc.{
    Repo,
    Enterprise.Flow,
    Enterprise.Flow.State,
    Enterprise.Organisation,
    Account,
    Account.User,
    Enterprise.ApprovalSystem,
    Enterprise.Plan,
    Enterprise.Membership,
    Enterprise.Membership.Payment,
    Document.Instance,
    Document
  }

  @default_states [%{"state" => "Draft", "order" => 1}, %{"state" => "Publish", "order" => 2}]
  @default_controlled_states [
    %{"state" => "Draft", "order" => 1},
    %{"state" => "Review", "order" => 2},
    %{"state" => "Publish", "order" => 3}
  ]

  @trial_plan_name "Free Trial"
  @trial_duration 14
  @doc """
  Get a flow from its UUID.
  """
  @spec get_flow(binary, User.t()) :: Flow.t() | nil
  def get_flow(flow_uuid, %{organisation_id: org_id}) do
    Repo.get_by(Flow, uuid: flow_uuid, organisation_id: org_id)
  end

  @doc """
  Get a state from its UUID and user's organisation.
  """
  @spec get_state(User.t(), Ecto.UUID.t()) :: State.t() | nil
  def get_state(%User{organisation_id: org_id}, <<_::288>> = state_uuid) do
    from(s in State, where: s.uuid == ^state_uuid and s.organisation_id == ^org_id) |> Repo.one()
  end

  def get_state(_, _), do: nil

  @doc """
  Create a controlled flow flow.
  """
  @spec create_flow(User.t(), map) ::
          %Flow{creator: User.t()} | {:error, Ecto.Changeset.t()}

  def create_flow(%{organisation_id: org_id} = current_user, %{"controlled" => true} = params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:flows)
    |> Flow.controlled_changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, flow} ->
        Task.start_link(fn -> create_default_states(current_user, flow, true) end)
        flow |> Repo.preload(:creator)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Create an uncontrolled flow flow.
  """

  def create_flow(%{organisation_id: org_id} = current_user, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:flows)
    |> Flow.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, flow} ->
        Task.start_link(fn -> create_default_states(current_user, flow) end)
        flow |> Repo.preload(:creator)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  List of all flows.
  """
  @spec flow_index(User.t(), map) :: map
  def flow_index(%User{organisation_id: org_id}, params) do
    from(f in Flow,
      where: f.organisation_id == ^org_id,
      order_by: [desc: f.id],
      preload: [:creator]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Show a flow.
  """
  @spec show_flow(binary, User.t()) :: Flow.t() | nil
  def show_flow(flow_uuid, user) do
    flow_uuid |> get_flow(user) |> Repo.preload([:creator, :states])
  end

  @doc """
  Update a controlled flow
  """
  def update_flow(flow, %User{id: id}, %{"controlled" => true} = params) do
    flow
    |> Flow.update_controlled_changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:ok, flow} ->
        flow |> Repo.preload(:creator)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Update a uncontrolled flow.
  """
  @spec update_flow(Flow.t(), User.t(), map) :: Flow.t() | {:error, Ecto.Changeset.t()}
  def update_flow(flow, %User{id: id}, params) do
    flow
    |> Flow.update_changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:ok, flow} ->
        flow |> Repo.preload(:creator)

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Delete a  flow.
  """
  @spec delete_flow(Flow.t(), User.t()) :: {:ok, Flow.t()} | {:error, Ecto.Changeset.t()}
  def delete_flow(flow, %User{id: id}) do
    flow
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :states,
      message:
        "Cannot delete the flow. Some States depend on this flow. Delete those states and then try again.!"
    )
    |> Spur.delete(%{actor: "#{id}", meta: flow})
  end

  @doc """
  Create default states for a controlled fow
  """

  @spec create_default_states(User.t(), Flow.t(), boolean()) :: list
  def create_default_states(current_user, flow, true) do
    Enum.map(@default_controlled_states, fn x -> create_state(current_user, flow, x) end)
  end

  @doc """
  Create default states for an uncontrolled flow
  """

  def create_default_states(current_user, flow) do
    Enum.map(@default_states, fn x -> create_state(current_user, flow, x) end)
  end

  @doc """
  Create a state under a flow.
  """
  @spec create_state(User.t(), Flow.t(), map) :: State.t() | {:error, Ecto.Changeset.t()}
  def create_state(%User{organisation_id: org_id} = current_user, flow, params) do
    params = params |> Map.merge(%{"organisation_id" => org_id})

    current_user
    |> build_assoc(:states, flow: flow)
    |> State.changeset(params)
    |> Spur.insert()
    |> case do
      {:ok, state} -> state
      {:error, _} = changeset -> changeset
    end
  end

  @doc """
  State index under a flow.
  """
  @spec state_index(binary, map) :: map
  def state_index(flow_uuid, params) do
    from(s in State,
      join: f in Flow,
      where: f.uuid == ^flow_uuid and s.flow_id == f.id,
      order_by: [desc: s.id],
      preload: [:flow, :creator]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Update a state.
  """
  @spec update_state(State.t(), User.t(), map) ::
          %State{creator: User.t(), flow: Flow.t()} | {:error, Ecto.Changeset.t()}
  def update_state(state, %User{id: id}, params) do
    state
    |> State.changeset(params)
    |> Spur.update(%{actor: "#{id}"})
    |> case do
      {:ok, state} ->
        state |> Repo.preload([:creator, :flow])

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Shuffle the order of flows.
  """
  @spec shuffle_order(State.t(), integer) :: list
  def shuffle_order(%{order: order, flow_id: flow_id}, additive) do
    from(s in State, where: s.flow_id == ^flow_id and s.order > ^order)
    |> Repo.all()
    |> Task.async_stream(fn x -> update_state_order(x, additive) end)
    |> Enum.to_list()
  end

  # Update the flow order by adding the additive.
  @spec update_state_order(State.t(), integer) :: {:ok, State.t()}
  defp update_state_order(%{order: order} = state, additive) do
    state
    |> State.order_update_changeset(%{order: order + additive})
    |> Repo.update()
  end

  @doc """
  Delete a state.
  """
  @spec delete_state(State.t(), User.t()) :: {:ok, State.t()} | {:error, Ecto.Changeset.t()}
  def delete_state(state, %User{id: id}) do
    state
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :instances,
      message:
        "Cannot delete the state. Some contents depend on this state. Update those states and then try again.!"
    )
    |> Spur.delete(%{actor: "#{id}", meta: state})
  end

  @doc """
  Get an organisation from its UUID.
  """

  @spec get_organisation(binary) :: Organisation.t() | nil
  def get_organisation(org_uuid) do
    Repo.get_by(Organisation, uuid: org_uuid)
  end

  @doc """
  Create an Organisation
  """

  @spec create_organisation(User.t(), map) :: {:ok, Organisation.t()}
  def create_organisation(%User{} = user, params) do
    user
    |> build_assoc(:organisation)
    |> Organisation.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, organisation} ->
        Task.start_link(fn -> create_membership(organisation) end)
        {:ok, organisation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Update an Organisation
  """

  @spec update_organisation(Organisation.t(), map) :: {:ok, Organisation.t()}
  def update_organisation(%Organisation{} = organisation, params) do
    organisation
    |> Organisation.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, %Organisation{} = organisation} ->
        {:ok, organisation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes the organisation
  """
  def delete_organisation(%Organisation{} = organisation) do
    organisation
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(
      :users,
      message:
        "Cannot delete the organisation. Some user depend on this organisation. Update those users and then try again.!"
    )
    |> Repo.delete()
  end

  @doc """
  Check the permission of the user wrt to the given organisation UUID.
  """
  @spec check_permission(User.t(), binary) :: Organisation.t() | nil | {:error, :no_permission}
  def check_permission(%User{role: %{name: "admin"}}, id) do
    get_organisation(id)
  end

  def check_permission(%User{organisation: %{uuid: id} = organisation}, id), do: organisation
  def check_permission(_, _), do: {:error, :no_permission}

  @doc """
  Check if a user with the given Email ID exists or not.
  """
  @spec already_member?(String.t()) :: :ok | {:error, :already_member}
  def already_member?(email) do
    Account.find(email)
    |> case do
      %User{} ->
        {:error, :already_member}

      _ ->
        :ok
    end
  end

  @doc """
  Send invitation email to given email.
  """

  @spec invite_team_member(User.t(), Organisation.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, any}
  def invite_team_member(%User{name: name}, %{name: org_name} = organisation, email) do
    token =
      Phoenix.Token.sign(WraftDocWeb.Endpoint, "organisation_invite", %{
        organisation: organisation,
        email: email
      })

    %{org_name: org_name, user_name: name, email: email, token: token}
    |> WraftDocWeb.Worker.EmailWorker.new(queue: "mailer", tags: ["invite"])
    |> Oban.insert()
  end

  @doc """
  Fetches the list of all members of current users organisation.
  """
  @spec members_index(User.t(), map) :: any
  def members_index(%User{organisation_id: organisation_id}, %{"name" => name} = params) do
    from(u in User,
      where: u.organisation_id == ^organisation_id,
      where: ilike(u.name, ^"%#{name}%"),
      preload: [:profile, :role, :organisation]
    )
    |> Repo.paginate(params)
  end

  def members_index(%User{organisation_id: organisation_id}, params) do
    from(u in User,
      where: u.organisation_id == ^organisation_id,
      preload: [:profile, :role, :organisation]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Create approval system
  """
  @spec create_approval_system(User.t(), map) ::
          ApprovalSystem.t() | {:error, Ecto.Changeset.t()}
  def create_approval_system(
        %{organisation_id: org_id} = current_user,
        %{
          "instance_id" => instance_id,
          "pre_state_id" => pre_state_id,
          "post_state_id" => post_state_id,
          "approver_id" => approver_id
        }
      ) do
    with %Instance{} = instance <- Document.get_instance(instance_id, current_user),
         %State{} = pre_state <- get_state(current_user, pre_state_id),
         %State{} = post_state <- get_state(current_user, post_state_id),
         %User{} = approver <- Account.get_user_by_uuid(approver_id) do
      params = %{
        instance_id: instance.id,
        pre_state_id: pre_state.id,
        post_state_id: post_state.id,
        approver_id: approver.id,
        organisation_id: org_id
      }

      do_create_approval_system(current_user, params)
    end
  end

  def create_approval_system(current_user, params) do
    do_create_approval_system(current_user, params)
  end

  defp do_create_approval_system(current_user, params) do
    current_user
    |> build_assoc(:approval_systems)
    |> ApprovalSystem.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, approval_system} ->
        approval_system
        |> Repo.preload([:instance, :pre_state, :post_state, :approver, :organisation, :user])

      {:error, _} = changeset ->
        changeset
    end
  end

  @doc """
  Get approval system by uuid
  """

  @spec get_approval_system(Ecto.UUID.t(), User.t()) :: ApprovalSystem.t()
  def get_approval_system(uuid, %{organisation_id: org_id}) do
    ApprovalSystem
    |> Repo.get_by(uuid: uuid, organisation_id: org_id)
    |> Repo.preload([:instance, :pre_state, :post_state, :approver, :organisation, :user])
  end

  @doc """
  Update an uproval system
  """
  @spec update_approval_system(User.t(), ApprovalSystem.t(), map) ::
          ApprovalSystem.t() | {:error, Ecto.Changeset.t()}
  def update_approval_system(current_user, approval_system, %{
        "instance_id" => instance_id,
        "pre_state_id" => pre_state_id,
        "post_state_id" => post_state_id,
        "approver_id" => approver_id
      }) do
    with %Instance{} = instance <- Document.get_instance(instance_id, current_user),
         %State{} = pre_state <- get_state(current_user, pre_state_id),
         %State{} = post_state <- get_state(current_user, post_state_id),
         %User{} = approver <- Account.get_user_by_uuid(approver_id) do
      params = %{
        instance_id: instance.id,
        pre_state_id: pre_state.id,
        post_state_id: post_state.id,
        approver_id: approver.id
      }

      approval_system
      |> ApprovalSystem.changeset(params)
      |> Repo.update()
      |> case do
        {:error, _} = changeset ->
          changeset

        {:ok, approval_system} ->
          approval_system
          |> Repo.preload([:instance, :pre_state, :post_state, :approver, :organisation, :user])
      end
    end
  end

  def update_approval_system(_user, approval_system, params) do
    approval_system
    |> ApprovalSystem.changeset(params)
    |> Repo.update()
    |> case do
      {:error, _} = changeset ->
        changeset

      {:ok, approval_system} ->
        approval_system
    end
  end

  @doc """
  Delete an approval system
  """
  @spec delete_approval_system(ApprovalSystem.t()) :: ApprovalSystem.t()
  def delete_approval_system(%ApprovalSystem{} = approval_system) do
    approval_system
    |> Repo.delete()
  end

  @doc """
  Check the user and approver is same while approving the content
  """
  def same_user?(current_user_uuid, approver_uuid) when current_user_uuid != approver_uuid,
    do: :invalid_user

  def same_user?(current_user_uuid, approver_uuid) when current_user_uuid === approver_uuid,
    do: true

  @doc """
  Check the prestate of the approval system and state of instance are same
  """
  def same_state?(prestate_id, state_id) when prestate_id != state_id,
    do: :unprocessible_state

  def same_state?(prestate_id, state_id) when prestate_id === state_id, do: true

  @doc """
  Approve a content by approval system
  """

  @spec approve_content(User.t(), ApprovalSystem.t()) :: ApprovalSystem.t()
  def approve_content(
        current_user,
        %ApprovalSystem{
          instance: instance,
          post_state: post_state
        } = approval_system
      ) do
    Document.update_instance_state(current_user, instance, post_state)

    proceed_approval(approval_system)
    |> Repo.preload(
      [
        :instance,
        :pre_state,
        :post_state,
        :approver,
        :user,
        :organisation
      ],
      force: true
    )
  end

  # Proceed approval make the status of approval system as approved

  @spec proceed_approval(ApprovalSystem.t()) :: ApprovalSystem.t()
  defp proceed_approval(approval_system) do
    params = %{approved: true, approved_log: NaiveDateTime.local_now()}

    approval_system
    |> ApprovalSystem.approve_changeset(params)
    |> Repo.update()
    |> case do
      {:ok, approval_system} ->
        approval_system

      {:error, changeset} = changeset ->
        changeset
    end
  end

  @doc """
  Creates a plan.
  """
  @spec create_plan(map) :: {:ok, Plan.t()}
  def create_plan(params) do
    %Plan{} |> Plan.changeset(params) |> Repo.insert()
  end

  @doc """
  Get a plan from its UUID.
  """
  @spec get_plan(Ecto.UUID.t()) :: Plan.t() | nil
  def get_plan(<<_::288>> = p_uuid) do
    Repo.get_by(Plan, uuid: p_uuid)
  end

  def get_plan(_), do: nil

  @doc """
  Get all plans.
  """
  @spec plan_index() :: [Plan.t()]
  def plan_index() do
    Plan |> Repo.all()
  end

  @doc """
  Updates a plan.
  """
  @spec update_plan(Plan.t(), map) :: {:ok, Plan.t()} | {:error, Ecto.Changeset.t()}
  def update_plan(%Plan{} = plan, params) do
    plan |> Plan.changeset(params) |> Repo.update()
  end

  def update_plan(_, _), do: nil

  @doc """
  Deletes a plan
  """
  @spec delete_plan(Plan.t()) :: {:ok, Plan.t()} | nil
  def delete_plan(%Plan{} = plan) do
    plan |> Repo.delete()
  end

  def delete_plan(_), do: nil

  # Create free trial membership for the given organisation.
  @spec create_membership(Organisation.t()) :: Membership.t()
  defp create_membership(%Organisation{id: id}) do
    plan = Repo.get_by(Plan, name: @trial_plan_name)
    start_date = Timex.now()
    end_date = start_date |> find_end_date(@trial_duration)
    params = %{start_date: start_date, end_date: end_date, plan_duration: @trial_duration}

    plan
    |> build_assoc(:memberships, organisation_id: id)
    |> Membership.changeset(params)
    |> Repo.insert!()
  end

  # Find the end date of a membership from the start date and duration of the
  # membership.
  @spec find_end_date(DateTime.t(), integer) :: DateTime.t() | nil
  defp find_end_date(start_date, duration) when is_integer(duration) do
    start_date |> Timex.shift(days: duration)
  end

  defp find_end_date(_, _), do: nil

  @doc """
  Gets a membership from its UUID.
  """
  def get_membership(<<_::288>> = m_uuid) do
    Membership |> Repo.get_by(uuid: m_uuid)
  end

  def get_membership(_), do: nil

  @doc """
  Same as get_membership/2, but also uses user's organisation ID to get the membership.
  When the user is admin no need to check the user's organisation.
  """
  @spec get_membership(Ecto.UUID.t(), User.t()) :: Membership.t() | nil
  def get_membership(<<_::288>> = m_uuid, %User{role: %{name: "admin"}}) do
    get_membership(m_uuid)
  end

  def get_membership(<<_::288>> = m_uuid, %User{organisation_id: org_id}) do
    Membership |> Repo.get_by(uuid: m_uuid, organisation_id: org_id)
  end

  def get_membership(_, _), do: nil

  @doc """
  Get membership of an organisation with the given UUID.
  """
  @spec get_organisation_membership(Ecto.UUID.t()) :: Membership.t() | nil
  def get_organisation_membership(<<_::288>> = o_uuid) do
    from(m in Membership,
      join: o in Organisation,
      on: o.id == m.organisation_id,
      where: o.uuid == ^o_uuid,
      preload: [:plan]
    )
    |> Repo.one()
  end

  def get_organisation_membership(_), do: nil

  @doc """
  Updates a membership.
  """
  @spec update_membership(User.t(), Membership.t(), Plan.t(), Razorpay.Payment.t()) ::
          Membership.t() | {:ok, Payment.t()} | {:error, :wrong_amount} | nil
  def update_membership(
        %User{} = user,
        %Membership{} = membership,
        %Plan{} = plan,
        %Razorpay.Payment{status: "failed"} = razorpay
      ) do
    params = create_payment_params(membership, plan, razorpay)
    create_payment_changeset(user, params) |> Repo.insert()
  end

  def update_membership(
        %User{} = user,
        %Membership{} = membership,
        %Plan{} = plan,
        %Razorpay.Payment{amount: amount} = razorpay
      ) do
    with duration when is_integer(duration) <- get_duration_from_plan_and_amount(plan, amount) do
      params = create_membership_and_payment_params(membership, plan, duration, razorpay)
      do_update_membership(user, membership, params)
    else
      error ->
        error
    end
  end

  def update_membership(_, _, _, _), do: nil

  # Update the membership and insert a new payment.
  @spec do_update_membership(User.t(), Membership.t(), map) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  defp do_update_membership(user, membership, params) do
    Multi.new()
    |> Multi.update(:membership, membership |> Membership.update_changeset(params))
    |> Multi.insert(:payment, create_payment_changeset(user, params))
    |> Repo.transaction()
    |> case do
      {:error, _, changeset, _} ->
        {:error, changeset}

      {:ok, %{membership: membership, payment: payment}} ->
        membership = membership |> Repo.preload([:plan, :organisation])

        Task.start_link(fn -> create_invoice(membership, payment) end)
        Task.start_link(fn -> create_membership_expiry_check_job(membership) end)

        membership
    end
  end

  # Create new payment.
  @spec create_payment_changeset(User.t(), map) :: Ecto.Changeset.t()
  defp create_payment_changeset(user, params) do
    user
    |> build_assoc(:payments, organisation_id: user.organisation_id)
    |> Payment.changeset(params)
  end

  # Create membership and payment params
  @spec create_membership_and_payment_params(
          Membership.t(),
          Plan.t(),
          integer(),
          Razorpay.Payment.t()
        ) :: map
  defp create_membership_and_payment_params(membership, plan, duration, razorpay) do
    start_date = Timex.now()
    end_date = start_date |> find_end_date(duration)

    create_payment_params(membership, plan, razorpay)
    |> Map.merge(%{
      start_date: start_date,
      end_date: end_date,
      plan_duration: duration,
      plan_id: plan.id
    })
  end

  # Create payment params
  @spec create_payment_params(Membership.t(), Plan.t(), Razorpay.Payment.t()) :: map
  defp create_payment_params(
         membership,
         plan,
         %Razorpay.Payment{amount: amount, id: r_id, status: status} = razorpay
       ) do
    status = status |> String.to_atom()
    status = Payment.statuses()[status]

    membership = membership |> Repo.preload([:plan])
    action = get_payment_action(membership.plan, plan)

    %{
      razorpay_id: r_id,
      amount: amount,
      status: status,
      action: action,
      from_plan_id: membership.plan_id,
      to_plan_id: plan.id,
      meta: razorpay,
      membership_id: membership.id
    }
  end

  # Gets the duration of selected plan based on the amount paid.
  @spec get_duration_from_plan_and_amount(Plan.t(), integer()) ::
          integer() | {:error, :wrong_amount}
  defp get_duration_from_plan_and_amount(%Plan{yearly_amount: amount}, amount), do: 365
  defp get_duration_from_plan_and_amount(%Plan{monthly_amount: amount}, amount), do: 30
  defp get_duration_from_plan_and_amount(_, _), do: {:error, :wrong_amount}

  # Gets the payment action comparing the old and new plans.
  @spec get_payment_action(Plan.t(), Plan.t()) :: integer
  defp get_payment_action(%Plan{id: id}, %Plan{id: id}) do
    Payment.actions()[:renew]
  end

  defp get_payment_action(%Plan{} = old_plan, %Plan{} = new_plan) do
    cond do
      old_plan.yearly_amount > new_plan.yearly_amount ->
        Payment.actions()[:downgrade]

      old_plan.yearly_amount < new_plan.yearly_amount ->
        Payment.actions()[:upgrade]
    end
  end

  # Create invoice and update payment.
  @spec create_invoice(Membership.t(), Payment.t()) :: {:ok, Payment.t()} | Ecto.Changeset.t()
  defp create_invoice(membership, payment) do
    invoice_number = generate_invoice_number(payment)

    invoice =
      Phoenix.View.render_to_string(
        WraftDocWeb.Api.V1.PaymentView,
        "invoice.html",
        membership: membership,
        invoice_number: invoice_number,
        payment: payment
      )

    {:ok, filename} =
      PdfGenerator.generate(invoice,
        page_size: "A4",
        delete_temporary: true,
        edit_password: "1234",
        filename: invoice_number
      )

    invoice = invoice_upload_struct(invoice_number, filename)

    upload_invoice(payment, invoice, invoice_number)
  end

  # Creates a background job that checks if the membership is expired on the date of membership expiry
  @spec create_membership_expiry_check_job(Membership.t()) :: Oban.Job.t()
  defp create_membership_expiry_check_job(%Membership{uuid: uuid, end_date: end_date}) do
    %{membership_uuid: uuid}
    |> WraftDocWeb.Worker.ScheduledWorker.new(scheduled_at: end_date, tags: ["plan_expiry"])
    |> Oban.insert!()
  end

  # Create invoice number from payment ID.
  defp generate_invoice_number(%{id: id}) do
    "WraftDoc-Invoice-" <> String.pad_leading("#{id}", 6, "0")
  end

  # Plug upload struct for uploading invoice
  defp invoice_upload_struct(invoice_number, filename) do
    %Plug.Upload{
      content_type: "application/pdf",
      filename: "#{invoice_number}.pdf",
      path: filename
    }
  end

  # Upload the invoice to AWS and link with payment transactions.
  defp upload_invoice(payment, invoice, invoice_number) do
    params = %{invoice: invoice, invoice_number: invoice_number}
    payment |> Payment.invoice_changeset(params) |> Repo.update!()
  end

  @doc """
  Gets the razorpay payment struct from the razorpay ID using `Razorpay.Payment.get/2`
  """
  @spec get_razorpay_data(binary) :: {:ok, Razorpay.Payment.t()} | Razorpay.error()
  def get_razorpay_data(razorpay_id) do
    Razorpay.Payment.get(razorpay_id)
  end

  @doc """
  Payment index with pagination.
  """
  @spec payment_index(integer, map) :: map
  def payment_index(org_id, params) do
    from(p in Payment,
      where: p.organisation_id == ^org_id,
      preload: [:organisation, :creator],
      order_by: [desc: p.id]
    )
    |> Repo.paginate(params)
  end

  @doc """
  Get a payment from its UUID.
  """
  @spec get_payment(Ecto.UUID.t(), User.t()) :: Payment.t() | nil
  def get_payment(<<_::288>> = payment_uuid, %{role: %{name: "admin"}}) do
    Payment |> Repo.get_by(uuid: payment_uuid)
  end

  def get_payment(<<_::288>> = payment_uuid, %{organisation_id: org_id}) do
    Payment |> Repo.get_by(uuid: payment_uuid, organisation_id: org_id)
  end

  def get_payment(_, _), do: nil

  @doc """
  Show a payment.
  """
  @spec show_payment(Ecto.UUID.t(), User.t()) :: Payment.t() | nil
  def show_payment(payment_uuid, user) do
    payment_uuid
    |> get_payment(user)
    |> Repo.preload([:organisation, :creator, :membership, :from_plan, :to_plan])
  end
end
