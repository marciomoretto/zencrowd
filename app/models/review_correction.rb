require 'set'

class ReviewCorrection < ApplicationRecord
  class Error < StandardError; end

  belongs_to :annotation
  belongs_to :reviewer, class_name: 'User'

  def self.original_payload(tile, annotation)
    if tile.tile_point_set
      tile.tile_point_set.as_zen_plot_payload[:points]
    else
      annotation.annotation_points.order(:id).map.with_index do |point, index|
        { id: index + 1, x: point.x, y: point.y }
      end
    end
  end

  def self.editor_points(tile, annotation, correction)
    return correction.points if correction
    return [] unless annotation

    original_payload(tile, annotation).map.with_index do |point, index|
      { x: point[:x], y: point[:y], source_id: index + 1 }
    end
  end

  def self.claim!(tile:, reviewer:)
    tile.with_lock do
      raise Error, 'O tile não está em revisão.' unless tile.submitted? || tile.in_review?

      annotation = tile.annotations.order(created_at: :desc, id: :desc).first
      raise Error, 'Nenhuma anotação encontrada para revisão.' unless annotation

      correction = find_by(annotation: annotation)
      if correction
        raise Error, 'Este envio já está sendo revisado por outra pessoa.' unless correction.reviewer_id == reviewer.id
        return correction
      end

      original = original_payload(tile, annotation)
      create!(
        annotation: annotation,
        reviewer: reviewer,
        original_points: original,
        points: original.map.with_index { |point, index| { x: point[:x], y: point[:y], source_id: index + 1 } }
      )
    end
  end

  def self.save_points!(tile:, reviewer:, points:, version:)
    raise Error, 'Formato de pontos inválido.' unless points.is_a?(Array)

    tile.with_lock do
      raise Error, 'O tile não está em revisão.' unless tile.submitted? || tile.in_review?

      annotation = tile.annotations.order(created_at: :desc, id: :desc).first
      raise Error, 'Nenhuma anotação encontrada para revisão.' unless annotation

      correction = find_by(annotation: annotation)
      if correction
        raise Error, 'Este envio já está sendo revisado por outra pessoa.' unless correction.reviewer_id == reviewer.id
        raise Error, 'As marcações foram alteradas em outra página. Atualize antes de salvar.' unless version == correction.lock_version
      else
        raise Error, 'As marcações foram alteradas em outra página. Atualize antes de salvar.' unless version.nil?

        original = original_payload(tile, annotation)
        correction = new(annotation: annotation, reviewer: reviewer, original_points: original)
      end

      normalized = TilePointSet.normalize_payload(axis: 'image', points: points)[:points]
      original = correction.original_points
      source_ids = Set.new
      reviewed = normalized.each_with_index.map do |point, index|
        raw_source = points[index][:source_id] || points[index]['source_id']
        source_id = raw_source.nil? ? nil : Integer(raw_source, exception: false)
        if !raw_source.nil? && (!source_id || source_id < 1 || source_id > original.size || source_ids.include?(source_id))
          raise Error, 'Identificação de ponto original inválida.'
        end
        if source_id
          source = original[source_id - 1]
          unless point[:x] == (source['x'] || source[:x]).to_f && point[:y] == (source['y'] || source[:y]).to_f
            raise Error, 'As coordenadas de um ponto original não podem ser alteradas.'
          end
          source_ids << source_id
        end
        { x: point[:x], y: point[:y], source_id: source_id }
      end

      correction.assign_attributes(
        points: reviewed,
        added_count: reviewed.count { |point| point[:source_id].nil? },
        removed_count: original.size - source_ids.size
      )
      correction.save!

      point_set = tile.tile_point_set || tile.build_tile_point_set
      point_set.assign_attributes(
        axis: 'image',
        points: reviewed.map.with_index { |point, index| { id: index + 1, x: point[:x], y: point[:y] } },
        finalized_at: point_set.finalized_at || Time.current
      )
      point_set.save!
      correction
    end
  rescue TilePointSet::PayloadError => e
    raise Error, e.message
  end
end
