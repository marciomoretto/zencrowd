class RoleSwitchesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_real_admin!

  def update
    role = params[:role].to_s

    unless User.roles.key?(role)
      return redirect_back fallback_location: dashboard_path, alert: 'Papel inválido.'
    end

    if role == 'admin'
      session.delete(:acting_role)
    else
      session[:acting_role] = role
    end

    redirect_to post_switch_path_for(role), notice: "Agora você está como #{helpers.user_role_label(role)}."
  end

  private

  def require_real_admin!
    return if current_user.real_admin?

    flash[:alert] = 'Permissão negada'
    redirect_to root_path
  end

  def post_switch_path_for(role)
    role == 'visitor' ? meus_dados_path : dashboard_path
  end
end
