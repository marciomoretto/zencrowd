class Uploader::RelatoriosController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_role!(:uploader, :admin) }
  before_action :set_evento
  before_action :set_relatorio, only: [:show, :edit, :update, :destroy]

  def show
    return redirect_to new_uploader_evento_relatorio_path(@evento) unless @relatorio
  end

  def new
    @relatorio = @evento.build_relatorio
  end

  def create
    @relatorio = @evento.build_relatorio(relatorio_params)

    if @relatorio.save
      redirect_to uploader_evento_relatorio_path(@evento), notice: 'Relatório criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @relatorio ||= @evento.build_relatorio
  end

  def update
    @relatorio ||= @evento.build_relatorio

    if @relatorio.update(relatorio_params)
      redirect_to uploader_evento_relatorio_path(@evento), notice: 'Relatório atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @relatorio&.destroy
      redirect_to uploader_evento_path(@evento), notice: 'Relatório removido com sucesso.'
    else
      redirect_to uploader_evento_relatorio_path(@evento), alert: 'Não foi possível remover o relatório.'
    end
  end

  private

  def set_evento
    @evento = Evento.find(params[:evento_id])
  end

  def set_relatorio
    @relatorio = @evento.relatorio
  end

  def relatorio_params
    params.require(:evento_relatorio).permit(:conteudo_md)
  end
end
