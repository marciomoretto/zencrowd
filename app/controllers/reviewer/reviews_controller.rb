module Reviewer
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_reviewer!

    def index
      @images = Image.where(status: [:submitted, :in_review])
    end

    def show
      @image = Image.find(params[:id])
      unless %w[submitted in_review].include?(@image.status)
        redirect_to reviewer_reviews_path, alert: 'Imagem não disponível para revisão.'
        return
      end
      @annotation = @image.annotations.order(created_at: :desc).first
      @points = @annotation&.annotation_points
    end
  end
end