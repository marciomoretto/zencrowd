class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_payment
  before_action :authorize_payment_access!

  def show
  end

  private

  def set_payment
    @payment = Payment.includes(:annotator, :processed_by, payment_items: :tile).find(params[:id])
  end

  def authorize_payment_access!
    return if @payment.annotator_id == current_user.id || current_user.admin? || current_user.finance?

    redirect_to root_path, alert: 'Permissão negada'
  end
end
