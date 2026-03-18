class ReviewerTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_reviewer!

  def index
    # Listar imagens submetidas para revisão
    @images = Image.where(status: [:submitted, :in_review])
  end
end
