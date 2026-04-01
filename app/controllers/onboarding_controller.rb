class OnboardingController < ApplicationController
  before_action :authenticate_user!

  def show
    if current_user.onboarding_completed?
      redirect_to dashboard_path and return
    end

    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(onboarding_params.merge(onboarding_completed: true))
      redirect_to dashboard_path, notice: 'Cadastro inicial concluido com sucesso.'
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def onboarding_params
    params.require(:user).permit(:cpf, :phone, :pix_key_type, :pix_key)
  end
end
