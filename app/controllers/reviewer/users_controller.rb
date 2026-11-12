module Reviewer
  class UsersController < ApplicationController
    include ReviewerTileSorting

    before_action :authenticate_user!
    before_action :authorize_reviewer!

    def index
      @users = paginate_scope(User.select(:id, :name).order(:name, :id))
    end

    def show
      @user = User.select(:id).find(params[:id])
      @sort = sort_param
      @direction = direction_param

      latest_annotations = Annotation.where(user_id: @user.id).where(
        'annotations.id = (SELECT latest.id FROM annotations latest WHERE latest.image_id = annotations.image_id ORDER BY latest.created_at DESC, latest.id DESC LIMIT 1)'
      )
      tiles = Tile.where(status: [:submitted, :in_review], id: latest_annotations.select(:image_id))
                  .includes(:tile_point_set, annotations: [:annotation_points, :review]).to_a
      @tiles = paginate_array_scope(apply_index_sort(tiles))
    end
  end
end
