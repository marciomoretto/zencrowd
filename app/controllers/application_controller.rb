class ApplicationController < ActionController::Base
  include Authorization
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

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

  def authorize_uploader!
    authorize_role!(:uploader)
  end

  # Allow annotators OR admins (for some endpoints)
  def authorize_annotator_or_admin!
    authorize_role!(:annotator, :admin)
  end

  # Allow annotators OR admins OR reviewers (for read-only preview endpoints)
  def authorize_annotator_or_admin_or_reviewer!
    authorize_role!(:annotator, :admin, :reviewer)
  end

  def pagination_per_page
    per = params[:per].to_i
    return DEFAULT_PER_PAGE if per <= 0

    [per, MAX_PER_PAGE].min
  end

  def pagination_page_number
    page = params[:page].to_i
    page > 0 ? page : 1
  end

  # Applies pagination when available (Kaminari), falling back to limit/offset.
  def paginate_scope(scope)
    return scope if scope.nil?

    if scope.respond_to?(:page)
      scope.page(params[:page]).per(pagination_per_page)
    elsif scope.respond_to?(:limit) && scope.respond_to?(:offset)
      scope.limit(pagination_per_page).offset((pagination_page_number - 1) * pagination_per_page)
    else
      paginate_array_scope(Array(scope))
    end
  end

  # Paginates Ruby arrays with Kaminari when available, otherwise slices locally.
  def paginate_array_scope(items)
    return Kaminari.paginate_array(items).page(params[:page]).per(pagination_per_page) if defined?(Kaminari)

    offset = (pagination_page_number - 1) * pagination_per_page
    items.slice(offset, pagination_per_page) || []
  end
end

