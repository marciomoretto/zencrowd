class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @finalized_tasks_count = 0
    load_admin_budget_data if current_user.admin?
    return unless current_user.annotator?

    @finalized_tasks_count = Annotation.where(user_id: current_user.id).distinct.count(:image_id)
  end

  private

  def load_admin_budget_data
    @total_paid = Tile.paid.sum(:task_value).to_d
    @total_reserved = Tile.reserved.sum(:task_value).to_d
    @budget_limit = AppSetting.budget_limit_reais.to_d

    @budget_committed = @total_paid + @total_reserved
    @budget_remaining = [@budget_limit - @budget_committed, 0].max
    @over_budget_amount = [@budget_committed - @budget_limit, 0].max

    if @budget_limit.positive?
      @paid_percentage = [(@total_paid / @budget_limit) * 100, 100.to_d].min
      remaining_bar = [100.to_d - @paid_percentage, 0].max
      reserved_raw = (@total_reserved / @budget_limit) * 100
      @reserved_percentage = [reserved_raw, remaining_bar].min
      @committed_percentage = (@budget_committed / @budget_limit) * 100
    else
      @paid_percentage = 0
      @reserved_percentage = 0
      @committed_percentage = 0
    end
  end
end
