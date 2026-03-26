class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def show
    load_settings
    render :index
  end

  def update
    AppSetting.update_operational_settings!(
      task_value_per_head_cents: settings_params[:task_value_per_head_cents],
      task_expiration_hours: settings_params[:task_expiration_hours],
      budget_limit_reais: settings_params[:budget_limit_reais],
      min_payment_reais: settings_params[:min_payment_reais],
      zenith_tolerance_degrees: settings_params[:zenith_tolerance_degrees]
    )

    redirect_to admin_settings_path, notice: 'Configurações atualizadas com sucesso.'
  rescue ArgumentError
    load_settings
    flash.now[:alert] = 'Preencha os campos com números inteiros válidos.'
    render :index, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    load_settings
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :index, status: :unprocessable_entity
  end

  private

  def settings_params
    params.require(:settings).permit(:task_value_per_head_cents, :task_expiration_hours, :budget_limit_reais, :min_payment_reais, :zenith_tolerance_degrees)
  end

  def load_settings
    @task_value_per_head_cents = AppSetting.task_value_per_head_cents
    @task_expiration_hours = AppSetting.task_expiration_hours
    @budget_limit_reais = AppSetting.budget_limit_reais
    @min_payment_reais = AppSetting.min_payment_reais
    @zenith_tolerance_degrees = AppSetting.zenith_tolerance_degrees
  end
end
