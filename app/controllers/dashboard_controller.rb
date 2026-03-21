class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @finalized_tasks_count = 0
    return unless current_user.annotator?

    @finalized_tasks_count = Annotation.where(user_id: current_user.id).distinct.count(:image_id)
  end
end
