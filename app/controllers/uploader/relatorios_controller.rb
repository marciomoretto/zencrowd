class Uploader::RelatoriosController < ApplicationController
  before_action :authenticate_user!
  before_action -> { authorize_role!(:uploader, :admin) }
  before_action :set_evento
  before_action :set_relatorio, only: [:show, :edit, :update, :destroy]

  def show
    return redirect_to new_uploader_evento_relatorio_path(@evento) unless @relatorio
  end

  def new
    if @evento.relatorio.present?
      return redirect_to edit_uploader_evento_relatorio_path(@evento)
    end

    @relatorio = @evento.build_relatorio(conteudo_md: default_report_template)
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

  def default_report_template
    stats = report_stats
    template_path = Rails.root.join('app/views/uploader/relatorios/templates/default.md.erb')
    template = File.read(template_path)

    ERB.new(template, trim_mode: '-').result_with_hash(stats: stats)
  end

  def report_stats
    imagens = @evento.imagens.to_a
    imagens_com_horario = imagens.select { |img| img.data_hora.present? }
    imagens_ordenadas_por_data = imagens_com_horario.sort_by { |img| img.data_hora }

    horarios_hash = imagens_com_horario.group_by { |img| img.data_hora.in_time_zone.strftime('%H:%M') }
    horarios_ordenados = horarios_hash.keys.sort
    _horario_pico_por_imagem, imagens_no_pico = horarios_hash.max_by { |(_hora, imgs)| imgs.size }

    pasta_pico = @evento.pasta_head_estimates
               .order(estimated_heads: :desc, pasta_nome: :asc)
               .first
    horario_pico = pasta_pico&.pasta_nome
    pasta_pico_nome = horario_pico.to_s.strip

    imagens_pico = if pasta_pico_nome.present?
                     imagens.select { |img| img.pasta.to_s.strip == pasta_pico_nome }
                   else
                     []
                   end

    tolerancia_zenital = AppSetting.zenith_tolerance_degrees
    imagem_pico_nao_zenital = imagens_pico.find do |img|
      img.arquivo.attached? && img.zenital?(tolerance_degrees: tolerancia_zenital) == false
    end

    imagem_pico_nao_zenital ||= imagens_pico.find { |img| img.arquivo.attached? }

    imagem_pico_nao_zenital_url = if imagem_pico_nao_zenital&.arquivo&.attached?
                                    rails_blob_path(imagem_pico_nao_zenital.arquivo, only_path: true)
                                  end

    mosaico_pico_url = latest_mosaic_preview_url_for_pasta(pasta_pico_nome)

    horario_inicio = imagens_ordenadas_por_data.first&.data_hora&.in_time_zone&.strftime('%H:%M')
    horario_fim = imagens_ordenadas_por_data.last&.data_hora&.in_time_zone&.strftime('%H:%M')

    pastas_horarios = imagens.filter_map { |img| img.pasta.to_s.strip.presence }.uniq.sort

    estimativa = pasta_pico&.estimated_heads
    estimativa = estimativa.to_i if estimativa.present?

    margem = 12
    min_estimado = estimativa.present? ? (estimativa * (1 - margem / 100.0)).round : nil
    max_estimado = estimativa.present? ? (estimativa * (1 + margem / 100.0)).round : nil

    local_texto = [@evento.local.presence, @evento.cidade.presence].compact.join(', ')
    local_texto = '[LOCAL, CIDADE]' if local_texto.blank?

    data_evento = @evento.data&.strftime('%d/%m/%Y')

    {
      manifestacao_nome: @evento.nome.presence || '[NOME DA MANIFESTACAO]',
      data_local_linha: "#{data_evento || '[DATA]'} | #{local_texto}",
      local_resumo: local_texto,
      data_resumo: data_evento || '[DATA]',
      numero_estimado: estimativa.present? ? estimativa.to_s : '[NUMERO]',
      margem: "#{margem}%",
      min_estimado: min_estimado.present? ? min_estimado.to_s : '[MIN]',
      max_estimado: max_estimado.present? ? max_estimado.to_s : '[MAX]',
      horario_pico: horario_pico.presence || '[HORARIO_PICO]',
      horario_inicio: horario_inicio.presence || '[HORARIO_INICIO]',
      horario_fim: horario_fim.presence || '[HORARIO_FIM]',
      n_horarios: horarios_ordenados.size.positive? ? horarios_ordenados.size.to_s : '[N_HORARIOS]',
      horarios: horarios_ordenados.any? ? horarios_ordenados.join(', ') : '[HORARIOS]',
      n_pastas: pastas_horarios.size.positive? ? pastas_horarios.size.to_s : '[N_PASTAS]',
      horarios_pastas: pastas_horarios.any? ? pastas_horarios.join(', ') : '[HORARIOS_PASTAS]',
      total_imagens: imagens.size.positive? ? imagens.size.to_s : '[TOTAL_IMAGENS]',
      n_selecionadas: imagens_no_pico.present? ? imagens_no_pico.size.to_s : '[N_SELECIONADAS]',
      link_evento_publico: evento_publico_path(@evento),
      imagem_pico_nao_zenital_url: imagem_pico_nao_zenital_url,
      mosaico_pico_url: mosaico_pico_url
    }
  end

  def latest_mosaic_preview_url_for_pasta(pasta_nome)
    return nil if pasta_nome.blank?

    mosaics_root = Rails.root.join('public', 'mosaics', "evento_#{@evento.id}", mosaic_safe_fragment(pasta_nome))
    return nil unless Dir.exist?(mosaics_root)

    pattern = File.join(mosaics_root.to_s, 'mosaic_*.{jpg,jpeg,png,webp,tif,tiff}')
    candidates = Dir.glob(pattern, File::FNM_CASEFOLD)
    return nil if candidates.empty?

    preferred_path = candidates.select { |path| File.basename(path).include?('_compressed') }.max_by { |path| File.mtime(path) }
    fallback_path = candidates.select { |path| File.basename(path).include?('_fallback') }.max_by { |path| File.mtime(path) }
    latest_any = candidates.max_by { |path| File.mtime(path) }
    selected_path = preferred_path || fallback_path || latest_any

    public_root = Rails.root.join('public').to_s
    relative = selected_path.to_s.sub(%r{\A#{Regexp.escape(public_root)}/?}, '')

    "/#{relative}"
  rescue StandardError
    nil
  end

  def mosaic_safe_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end
end
