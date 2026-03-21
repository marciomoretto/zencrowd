class AnnotatorTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!
  before_action :expire_stale_reservations!

  def available
    @reserved_tile = Tile.find_by(reserver: current_user, status: :reserved)
    @rejected_tiles_count = Tile.where(reserver: current_user, status: :rejected).count

    @sort = available_sort_param
    @direction = available_direction_param
    @status_filter = available_status_filter_param

    scope = Tile.where(status: [:available, :abandoned]).includes(:tile_point_set, annotations: :annotation_points)
    scope = scope.where(status: @status_filter) if @status_filter.present?
    @tiles = apply_available_sort(scope)
    @task_is_new_by_tile_id = build_task_novelty_index(@tiles)
  end

  def my_task
    Image.reserve_next_rejected_for!(current_user)
    @tile = Tile.find_by(reserver: current_user, status: :reserved)
    # Mensagens de flash já são exibidas na view se existirem
  end

  def completed
    @completed_sort = completed_sort_param
    @completed_direction = completed_direction_param
    @completed_status_filter = completed_status_filter_param
    @current_task_tile_id = current_task_tile_for(current_user)&.id

    all_annotations = finalized_annotations_for(current_user)
    present_statuses = all_annotations.map { |annotation| completed_status_for(annotation) }.compact.uniq
    @completed_status_options = Image.statuses.keys.select { |status| present_statuses.include?(status) }

    @completed_status_filter = nil unless @completed_status_options.include?(@completed_status_filter)

    @paid_tasks_total_value = tasks_total_for_status(all_annotations, 'paid')
    @to_pay_tasks_total_value = tasks_total_for_status(all_annotations, 'approved')

    filtered_annotations = if @completed_status_filter.present?
                             all_annotations.select { |annotation| completed_status_for(annotation) == @completed_status_filter }
                           else
                             all_annotations
                           end

    @finalized_annotations = sort_completed_annotations(filtered_annotations)
  end

  private

  def expire_stale_reservations!
    Tile.expire_all_reservations!
  end

  def finalized_annotations_for(user)
    seen_image_ids = {}

    Annotation
      .includes(:image, :annotation_points, :review)
      .where(user_id: user.id)
      .order(submitted_at: :desc, created_at: :desc)
      .each_with_object([]) do |annotation, result|
        next if annotation.image.nil?
        next if seen_image_ids[annotation.image_id]

        seen_image_ids[annotation.image_id] = true
        result << annotation
      end
  end

  def tasks_total_for_status(finalized_annotations, status)
    finalized_annotations.sum do |annotation|
      tile = annotation.image
      next 0.0 unless tile&.status == status

      tile.task_value.to_f
    end
  end

  def completed_status_for(annotation)
    tile = annotation.image
    return nil unless tile

    return 'rejected' if tile.status == 'reserved' && annotation.review&.rejected?

    tile.status
  end

  def available_sort_param
    sort = params[:sort].to_s
    %w[id task_value].include?(sort) ? sort : 'id'
  end

  def available_status_filter_param
    status = params[:status].to_s
    %w[available abandoned].include?(status) ? status : nil
  end

  def available_direction_param
    params[:direction].to_s.downcase == 'desc' ? 'desc' : 'asc'
  end

  def apply_available_sort(scope)
    if @sort == 'task_value'
      scope.order(Arel.sql("task_value IS NULL, task_value #{@direction}, id ASC"))
    else
      scope.order(id: @direction)
    end
  end

  def build_task_novelty_index(tiles)
    tiles.each_with_object({}) do |tile, index|
      index[tile.id] = tile.available?
    end
  end

  def completed_sort_param
    sort = params[:sort].to_s
    %w[task_id task_value total_points finalized_at].include?(sort) ? sort : 'finalized_at'
  end

  def completed_direction_param
    params[:direction].to_s.downcase == 'asc' ? 'asc' : 'desc'
  end

  def completed_status_filter_param
    status = params[:status].to_s
    Image.statuses.key?(status) ? status : nil
  end

  def sort_completed_annotations(annotations)
    annotations.sort_by do |annotation|
      tile = annotation.image
      sort_value = case @completed_sort
                   when 'task_id'
                     tile&.id
                   when 'task_value'
                     tile&.task_value
                   when 'total_points'
                     annotation.annotation_points.size
                   else
                     (annotation.submitted_at || annotation.created_at)&.to_i
                   end

      [completed_numeric_sort_key(sort_value), annotation.id]
    end
  end

  def completed_numeric_sort_key(value)
    return [1, 0] if value.nil?

    numeric_value = value.to_f
    [0, @completed_direction == 'asc' ? numeric_value : -numeric_value]
  end

  def current_task_tile_for(user)
    Tile.find_by(reserver: user, status: :reserved) ||
      Tile.where(reserver: user, status: :rejected).order(updated_at: :desc, id: :desc).first
  end
end
