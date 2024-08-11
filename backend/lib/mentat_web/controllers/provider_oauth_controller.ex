defmodule MentatWeb.ProviderOAuthController do
  alias Mentat.Integrations
  use MentatWeb, :controller

  def request(conn, %{"provider" => provider_str}) do
    # TODO: make sure to do a string to atom fix here
    provider = String.to_atom(provider_str)

    config = config!(provider)

    config[:strategy].authorize_url(config)
    |> case do
      {:ok, %{url: url, session_params: session_params}} ->
        conn = put_session(conn, :session_params, session_params)

        conn
        |> put_resp_header("location", url)
        |> send_resp(302, "")

      {:error, error} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          500,
          "Something went wrong generating the request authorization url: #{inspect(error)}"
        )
    end
  end

  def callback(conn, params) do
    session_params = get_session(conn, :session_params)
    provider = params["provider"] |> String.to_atom()

    config = config!(provider)

    config
    |> Assent.Config.put(:session_params, session_params)
    |> config[:strategy].callback(params)
    |> case do
      {:ok, %{user: _user, token: oauth_response}} ->
        Integrations.save_provider(provider, conn.assigns.current_user.id, %{
          name: provider,
          status: :enabled,
          token: oauth_response["access_token"],
          expires_at: DateTime.add(DateTime.utc_now(), oauth_response["expires_in"], :second),
          refresh_token: oauth_response["refresh_token"],
          provider_uid: oauth_response["user_id"],
          token_type: oauth_response["token_type"]
        })

        conn
        |> Phoenix.Controller.redirect(to: "/")

      {:error, error} ->
        # Authorizaiton failed
        IO.inspect(error, label: "error")

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, inspect(error, pretty: true))
    end
  end

  defp config!(provider) do
    Application.get_env(:mentat, :strategies)[provider] ||
      raise "No provider configuration for #{provider}"
  end
end
