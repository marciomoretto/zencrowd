class ReviewerTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_reviewer!

  def index
    # Listar tiles submetidos para revisão
    @tiles = Tile.where(status: [:submitted, :in_review])
  end
end
