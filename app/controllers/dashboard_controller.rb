class DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!, only: :request_payment

  def index
    @finalized_tasks_count = 0
    load_admin_budget_data if current_user.admin?
    return load_annotator_payment_data if current_user.annotator?

    @finalized_tasks_count = Annotation.where(user_id: current_user.id).distinct.count(:image_id)
  end

  def request_payment
    result = Image.request_payment_for!(current_user, min_payment_reais: AppSetting.min_payment_reais)
    redirect_to dashboard_path, notice: "Solicitação de pagamento registrada com sucesso para #{result[:updated_count]} tarefa(s)."
  rescue Image::StateMachineError => e
    redirect_to dashboard_path, alert: e.message
  end

  private

  def load_annotator_payment_data
    @finalized_tasks_count = Annotation.where(user_id: current_user.id).distinct.count(:image_id)
    @approved_annotations = approved_annotations_for(current_user)
    @requested_annotations = payment_requested_annotations_for(current_user)
    @paid_annotations = paid_annotations_for(current_user)
    @approved_tasks_total_value = @approved_annotations.sum { |annotation| annotation.image&.task_value.to_d }
    @requested_payment_total_value = @requested_annotations.sum { |annotation| annotation.image&.task_value.to_d }
    @paid_tasks_total_value = @paid_annotations.sum { |annotation| annotation.image&.task_value.to_d }
    @to_receive_total_value = @approved_tasks_total_value
    @min_payment_reais = AppSetting.min_payment_reais.to_d
    @can_request_payment = @to_receive_total_value.positive? && @to_receive_total_value >= @min_payment_reais
  end

  def approved_annotations_for(user)
    annotations_for_status(user, :approved)
  end

  def payment_requested_annotations_for(user)
    annotations_for_status(user, :payment_requested)
  end

  def paid_annotations_for(user)
    annotations_for_status(user, :paid)
  end

  def annotations_for_status(user, status)
    seen_image_ids = {}

    Annotation
      .includes(:image)
      .where(user_id: user.id)
      .order(submitted_at: :desc, created_at: :desc)
      .each_with_object([]) do |annotation, result|
        tile = annotation.image
        next unless tile&.status == status.to_s
        next if seen_image_ids[annotation.image_id]

        seen_image_ids[annotation.image_id] = true
        result << annotation
      end
  end

  def load_admin_budget_data
    @total_paid = Tile.paid.sum(:task_value).to_d
    @total_to_pay = Tile.to_pay.sum(:task_value).to_d
    @budget_limit = AppSetting.budget_limit_reais.to_d

    @budget_committed = @total_paid + @total_to_pay
    @budget_remaining = [@budget_limit - @budget_committed, 0].max
    @over_budget_amount = [@budget_committed - @budget_limit, 0].max

    if @budget_limit.positive?
      @paid_percentage = [(@total_paid / @budget_limit) * 100, 100.to_d].min
      remaining_bar = [100.to_d - @paid_percentage, 0].max
      to_pay_raw = (@total_to_pay / @budget_limit) * 100
      @to_pay_percentage = [to_pay_raw, remaining_bar].min
      @committed_percentage = (@budget_committed / @budget_limit) * 100
    else
      @paid_percentage = 0
      @to_pay_percentage = 0
      @committed_percentage = 0
    end
  end
end
