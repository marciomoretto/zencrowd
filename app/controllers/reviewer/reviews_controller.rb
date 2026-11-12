module Reviewer
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_reviewer!

    def index
      @status_filter = status_filter_param
      @annotator_filter = annotator_filter_param
      @sort = sort_param
      @direction = direction_param

      allowed_statuses = [:reserved, :submitted, :in_review, :approved, :rejected, :paid]
      base_scope = Tile.where(status: allowed_statuses)

      @annotators = User.where(id: base_scope.where.not(reserver_id: nil).distinct.select(:reserver_id)).order(:name)

      base_scope = base_scope.where(status: @status_filter) if @status_filter.present?
      base_scope = base_scope.where(reserver_id: @annotator_filter) if @annotator_filter.present?

      tiles = base_scope.includes(:reserver, :tile_point_set, annotations: [:annotation_points, :review]).to_a
      sorted_tiles = apply_index_sort(tiles)
      @tiles = paginate_array_scope(sorted_tiles)
    end

    def show
      @tile = Tile.find(params[:id])
      unless %w[reserved submitted in_review approved rejected paid].include?(@tile.status)
        redirect_to reviewer_reviews_path, alert: 'Tile não disponível para revisão.'
        return
      end
      @annotation = @tile.annotations.order(created_at: :desc, id: :desc).first
      @correction = @annotation&.review_correction unless @tile.reserved?
      @editor_points = ReviewCorrection.editor_points(@tile, @annotation, @correction)
      @editable = current_user.reviewer? && %w[submitted in_review].include?(@tile.status) && @annotation.present? &&
                  (@correction.nil? || @correction.reviewer_id == current_user.id)
    end

    def claim
      return render json: { error: 'É necessário atuar como revisor.' }, status: :forbidden unless current_user.reviewer?

      correction = ReviewCorrection.claim!(tile: Tile.find(params[:id]), reviewer: current_user)
      render json: { version: correction.lock_version, points: correction.points }
    rescue ReviewCorrection::Error, ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def points
      return render json: { error: 'É necessário atuar como revisor.' }, status: :forbidden unless current_user.reviewer?

      tile = Tile.find(params[:id])
      raw_points = params[:points]
      raw_points = raw_points.map { |point| point.respond_to?(:to_unsafe_h) ? point.to_unsafe_h : point } if raw_points.is_a?(Array)
      version = params[:version].nil? ? nil : Integer(params[:version], exception: false)
      if !params[:version].nil? && version.nil?
        return render json: { error: 'Versão inválida.' }, status: :unprocessable_entity
      end

      correction = ReviewCorrection.save_points!(tile: tile, reviewer: current_user, points: raw_points, version: version)
      render json: { version: correction.lock_version, added_count: correction.added_count, removed_count: correction.removed_count }
    rescue ReviewCorrection::Error, ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def sort_param
      sort = params[:sort].to_s
      %w[estimated_count marked_count progress].include?(sort) ? sort : nil
    end

    def status_filter_param
      status = params[:status].to_s
      %w[reserved submitted in_review approved rejected paid].include?(status) ? status : nil
    end

    def annotator_filter_param
      value = params[:annotator_id].to_s
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError
      nil
    end

    def direction_param
      params[:direction].to_s.downcase == 'desc' ? 'desc' : 'asc'
    end

    def apply_index_sort(tiles)
      return tiles.sort_by(&:updated_at).reverse unless @sort.present?

      tiles.sort_by do |tile|
        latest_annotation = tile.annotations.max_by(&:created_at)
        marked_count = tile.tile_point_set ? tile.tile_point_set.points.size : latest_annotation&.annotation_points&.size.to_i
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