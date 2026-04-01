class SessionsController < ApplicationController
  skip_before_action :redirect_incomplete_onboarding!
  skip_before_action :logout_if_blocked_user!, only: [:new, :callback]
  layout 'public'

  def new
    client = SenhaUnicaUSP::Client.new(session: session)
    redirect_to client.authorization_url, allow_other_host: true
  rescue StandardError => e
    Rails.logger.error("[SessionsController#new] #{e.class}: #{e.message}")
    redirect_to root_path, alert: 'Nao foi possivel iniciar o login USP.'
  end

  def callback
    verifier = params[:oauth_verifier].to_s
    if verifier.blank?
      redirect_to root_path, alert: 'Resposta invalida da autenticacao USP.' and return
    end

    client = SenhaUnicaUSP::Client.new(session: session)
    payload = client.fetch_payload!(oauth_verifier: verifier)

    usp_login = payload['loginUsuario'].to_s.strip
    if usp_login.blank?
      redirect_to root_path, alert: 'Nao foi possivel identificar seu usuario USP.' and return
    end

    user = User.find_by(usp_login: usp_login)
    if user.nil?
      email = payload['emailPrincipalUsuario'].to_s.strip
      user = User.find_by(email: email) if email.present?
    end

    if user.nil?
      user = User.new(
        usp_login: usp_login,
        email: payload['emailPrincipalUsuario'].to_s.strip.presence || "#{usp_login}@usp.br",
        name: payload['nomeUsuario'].to_s.strip.presence || usp_login,
        role: :annotator,
        onboarding_completed: false,
        password: SecureRandom.hex(24)
      )
      user.password_confirmation = user.password
      user.save!
    elsif user.usp_login.blank?
      user.update!(usp_login: usp_login)
    end

    if user.blocked?
      reset_session
      redirect_to root_path, alert: 'Sua conta esta bloqueada. Procure um administrador.' and return
    end

    session[:user_id] = user.id
    redirect_to(user.onboarding_completed? ? dashboard_path : onboarding_path)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[SessionsController#callback] #{e.class}: #{e.message}")
    redirect_to root_path, alert: e.record.errors.full_messages.to_sentence
  rescue StandardError => e
    Rails.logger.error("[SessionsController#callback] #{e.class}: #{e.message}")
    redirect_to root_path, alert: 'Falha ao concluir login com a USP.'
  end

  def destroy
    reset_session
    redirect_to root_path, notice: 'Logout realizado com sucesso.'
  end
end
