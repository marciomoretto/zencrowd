class AnnotatorTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!

  def available
    # Só mostra imagens disponíveis se o usuário não tiver nenhuma reservada
    if Image.where(reserver: current_user, status: :reserved).exists?
      flash[:alert] = 'Você já possui uma imagem reservada. Conclua ou libere antes de reservar outra.'
      return redirect_to my_task_path
    end

    @images = Image.where(status: :available).order(:id)
  end

  def my_task
    @image = Image.find_by(reserver: current_user, status: :reserved)
    # Mensagens de flash já são exibidas na view se existirem
  end
end
