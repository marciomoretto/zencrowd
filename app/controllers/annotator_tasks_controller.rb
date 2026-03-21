class AnnotatorTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!
  before_action :expire_stale_reservations!

  def available
    # Só mostra tiles disponíveis se o usuário não tiver nenhum reservado
    if Tile.where(reserver: current_user, status: :reserved).exists?
      flash[:alert] = 'Você já possui um tile reservado. Conclua ou libere antes de reservar outro.'
      return redirect_to my_task_path
    end

    @sort = available_sort_param
    @direction = available_direction_param

    scope = Tile.where(status: :available).includes(:tile_point_set, annotations: :annotation_points)
    @tiles = apply_available_sort(scope)
    @task_is_new_by_tile_id = build_task_novelty_index(@tiles)
  end

  def my_task
    @tile = Tile.find_by(reserver: current_user, status: :reserved)
    # Mensagens de flash já são exibidas na view se existirem
  end

  def completed
    @finalized_annotations = finalized_annotations_for(current_user)
    @paid_tasks_total_value = tasks_total_for_status(@finalized_annotations, 'paid')
    @to_pay_tasks_total_value = tasks_total_for_status(@finalized_annotations, 'approved')
  end

  private

  def expire_stale_reservations!
    Tile.expire_all_reservations!
  end

  def finalized_annotations_for(user)
    seen_image_ids = {}

    Annotation
      .includes(:image, :annotation_points)
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

  def available_sort_param
    sort = params[:sort].to_s
    %w[id task_value is_new].include?(sort) ? sort : 'id'
  end

  def available_direction_param
    params[:direction].to_s.downcase == 'desc' ? 'desc' : 'asc'
  end

  def apply_available_sort(scope)
    if @sort == 'task_value'
      scope.order(Arel.sql("task_value IS NULL, task_value #{@direction}, id ASC"))
    elsif @sort == 'is_new'
      tiles = scope.to_a
      novelty_index = build_task_novelty_index(tiles)

      tiles.sort_by do |tile|
        novelty_value = novelty_index[tile.id] ? 0 : 1
        @direction == 'asc' ? [novelty_value, tile.id] : [1 - novelty_value, tile.id]
      end
    else
      scope.order(id: @direction)
    end
  end

  def build_task_novelty_index(tiles)
    tiles.each_with_object({}) do |tile, index|
      has_tile_points = tile.tile_point_set&.points.to_a.any?
      has_annotation_points = tile.annotations.any? { |annotation| annotation.annotation_points.any? }

      index[tile.id] = !(has_tile_points || has_annotation_points)
    end
  end
end
