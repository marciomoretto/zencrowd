class ReviewerTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_reviewer!

  def index
    # Stub: lógica para tarefas em revisão
    flash[:notice] = 'Tarefas em revisão não implementadas.'
    redirect_to root_path
  end
end
