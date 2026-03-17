class ApplicationController < ActionController::Base
  include Authorization

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

  # Confirms a logged-in user
  def authenticate_user!
    unless authenticated?
      render json: { error: 'Autenticação necessária' }, status: :unauthorized
    end
  end

  # Confirms the correct role
  def authorize_role!(*roles)
    unless authenticated? && roles.map(&:to_s).include?(current_user.role)
      render json: { error: 'Permissão negada' }, status: :forbidden
    end
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
end

