class MeusDadosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def show
  end

  def edit
  end

  def update
    if @user.update(meus_dados_params)
      redirect_to edit_meus_dados_path, notice: 'Dados atualizados com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = current_user
  end

  def meus_dados_params
    params.require(:user).permit(:cpf, :phone, :pix_key_type, :pix_key)
  end
end
