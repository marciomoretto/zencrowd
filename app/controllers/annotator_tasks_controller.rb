class AnnotatorTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_annotator!

  def available
    # Stub: lógica para imagens disponíveis
    flash[:notice] = 'Lista de imagens disponíveis não implementada.'
    redirect_to root_path
  end

  def my_task
    # Stub: lógica para tarefa atual do anotador
    flash[:notice] = 'Minha tarefa não implementada.'
    redirect_to root_path
  end
end
