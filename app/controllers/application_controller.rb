class ApplicationController < ActionController::Base
  include Authorization
  layout 'logged'
  before_action :logout_if_blocked_user!

  # Helper methods available in all controllers
  helper_method :current_user, :authenticated?

  private

  # Returns the currently logged-in user (if any)
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # Returns true if the user is logged in, false otherwise
  def authenticated?
    current_user.present?
  end

  # Sends already authenticated users to their private area.
  def redirect_authenticated_user_to_dashboard!
    return unless request.format.html?
    return unless authenticated?

    redirect_to dashboard_path
  end

  # Ends the session for users blocked after logging in
  def logout_if_blocked_user!
    return unless session[:user_id]
    return unless current_user&.blocked?

    reset_session
    @current_user = nil

    respond_to do |format|
      format.html do
        flash[:alert] = 'Sua conta foi bloqueada. Procure um administrador.'
        redirect_to login_path
      end
      format.json do
        render json: { error: 'Usuário bloqueado. Procure um administrador.' }, status: :forbidden
      end
      format.any { head :forbidden }
    end
  end

  # Confirms a logged-in user
  def authenticate_user!
    unless authenticated?
      if request.format.json?
        render json: { error: 'Autenticação necessária' }, status: :unauthorized
      else
        flash[:alert] = 'Você precisa estar logado para acessar esta página.'
        redirect_to login_path
      end
      return false
    end
    true
  end

  # Confirms the correct role
  def authorize_role!(*roles)
    unless authenticated? && roles.map(&:to_s).include?(current_user.role)
      if request.format.json?
        render json: { error: 'Permissão negada' }, status: :forbidden
      else
        flash[:alert] = 'Permissão negada'
        redirect_to root_path
      end
      return false
    end
    true
  end

  # Role-specific authorization methods
  def authorize_admin!
    authorize_role!(:admin)
  end

  def authorize_annotator!
    authorize_role!(:annotator)
  end

  def authorize_reviewer!
    authorize_role!(:reviewer)
  end

  # Allow annotators OR admins (for some endpoints)
  def authorize_annotator_or_admin!
    authorize_role!(:annotator, :admin)
  end

  # Allow annotators OR admins OR reviewers (for read-only preview endpoints)
  def authorize_annotator_or_admin_or_reviewer!
    authorize_role!(:annotator, :admin, :reviewer)
  end
end

