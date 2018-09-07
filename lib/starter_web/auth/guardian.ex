defmodule StarterWeb.Guardian do
  @moduledoc """
    The main Guardian module. Responsible for selecting the subject
    for token geration and retrieving subject from the token.
  """
  use Guardian, otp_app: :starter
  alias Starter.Repo
  alias Starter.UserManagement.User

  def subject_for_token(resource, _claims) do
    # You can use any value for the subject of your token but
    # it should be useful in retrieving the resource later, see
    # how it being used on `resource_from_claims/1` function.
    # A unique `id` is a good subject, a non-unique email address
    # is a poor subject.
    sub = to_string(resource.email)
    {:ok, sub}
  end

  def subject_for_token(_, _) do
    {:error, :reason_for_error}
  end

  def resource_from_claims(claims) do
    # Here we'll look up our resource from the claims, the subject can be
    # found in the `"sub"` key. In `above subject_for_token/2` we returned
    # the resource id so here we'll rely on that to look it up.
    email = claims["sub"]
    {:ok, email}
  end

  def resource_from_claims(_claims) do
    {:error, :reason_for_error}
  end
end
