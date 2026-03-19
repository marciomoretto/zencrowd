class AnnotatorTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!

  def available
    # Só mostra tiles disponíveis se o usuário não tiver nenhum reservado
    if Tile.where(reserver: current_user, status: :reserved).exists?
      flash[:alert] = 'Você já possui um tile reservado. Conclua ou libere antes de reservar outro.'
      return redirect_to my_task_path
    end

    @tiles = Tile.where(status: :available).order(:id)
  end

  def my_task
    @tile = Tile.find_by(reserver: current_user, status: :reserved)
    # Mensagens de flash já são exibidas na view se existirem
  end
end
