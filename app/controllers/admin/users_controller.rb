class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_user, only: [:toggle_block, :update_role]
  before_action :prevent_self_management!, only: [:toggle_block, :update_role]

  def index
    @users = User.order(created_at: :desc)
  end

  def toggle_block
    @user.update!(blocked: !@user.blocked?)

    if @user.blocked?
      flash[:notice] = "Usuário #{@user.name} foi bloqueado."
    else
      flash[:notice] = "Usuário #{@user.name} foi desbloqueado."
    end

    redirect_to admin_users_path
  end

  def update_role
    new_role = params[:role].to_s

    unless User.roles.key?(new_role)
      flash[:alert] = 'Papel inválido.'
      return redirect_to admin_users_path
    end

    if @user.update(role: new_role)
      flash[:notice] = "Papel de #{@user.name} atualizado para #{new_role}."
    else
      flash[:alert] = @user.errors.full_messages.to_sentence
    end

    redirect_to admin_users_path
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def prevent_self_management!
    return unless @user == current_user

    flash[:alert] = 'Você não pode alterar seu próprio usuário nesta tela.'
    redirect_to admin_users_path
  end
end
