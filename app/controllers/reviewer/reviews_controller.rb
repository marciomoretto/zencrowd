module Reviewer
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_reviewer!

    def index
      @sort = sort_param
      @direction = direction_param

      tiles = Tile.where(status: [:reserved, :submitted, :in_review, :approved, :rejected, :paid])
                  .includes(:reserver, annotations: [:annotation_points, :review])
                  .to_a

      @tiles = apply_index_sort(tiles)
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

    private

    def sort_param
      sort = params[:sort].to_s
      %w[estimated_count marked_count progress].include?(sort) ? sort : nil
    end

    def direction_param
      params[:direction].to_s.downcase == 'desc' ? 'desc' : 'asc'
    end

    def apply_index_sort(tiles)
      return tiles.sort_by(&:updated_at).reverse unless @sort.present?

      tiles.sort_by do |tile|
        latest_annotation = tile.annotations.max_by(&:created_at)
        marked_count = latest_annotation&.annotation_points&.size.to_i
        estimated_count = tile.head_count
        progress = if estimated_count.present? && estimated_count.positive?
                     (marked_count.to_f / estimated_count) * 100
                   end

        sort_value = case @sort
                     when 'estimated_count' then estimated_count
                     when 'marked_count' then marked_count
                     when 'progress' then progress
                     end

        [numeric_sort_key(sort_value), tile.id]
      end
    end

    def numeric_sort_key(value)
      return [1, 0] if value.nil?

      [0, @direction == 'asc' ? value.to_f : -value.to_f]
    end
  end
end