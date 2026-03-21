module Reviewer
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_reviewer!

    def index
      @tiles = Tile.where(status: [:reserved, :submitted, :in_review, :approved, :rejected, :paid])
                   .includes(:reserver, annotations: [:annotation_points, :review])
                   .order(updated_at: :desc)
    end

    def show
      @tile = Tile.find(params[:id])
      unless %w[reserved submitted in_review approved rejected paid].include?(@tile.status)
        redirect_to reviewer_reviews_path, alert: 'Tile não disponível para revisão.'
        return
      end
      @annotation = @tile.annotations.order(created_at: :desc).first
      @points = @annotation&.annotation_points
    end
  end
end