class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    # SE O UTILIZADOR ESTIVER A TENTAR MUDAR A SENHA
    if params[:user][:current_password].present? || params[:user][:password].present?
      
      # Verifica se a senha atual está correta
      if @user.authenticate(params[:user][:current_password])
        if @user.update(password_params)
          flash[:notice] = "A sua senha foi atualizada com sucesso!"
          redirect_to profile_path
        else
          render :edit, status: :unprocessable_entity
        end
      else
        @user.errors.add(:current_password, "atual está incorreta.")
        render :edit, status: :unprocessable_entity
      end

    # SE O UTILIZADOR ESTIVER A TENTAR MUDAR APENAS OS DADOS BÁSICOS (NOME)
    else
      if @user.update(info_params)
        flash[:notice] = "Os seus dados foram atualizados com sucesso!"
        redirect_to profile_path
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  # Parâmetros permitidos apenas para a secção de Informações
  def info_params
    params.require(:user).permit(:name)
  end

  # Parâmetros permitidos apenas para a secção de Segurança
  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end