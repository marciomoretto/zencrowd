namespace :imagens do
  desc 'Reprocessa metadados de todas as imagens cadastradas'
  task reprocessar_metadados: :environment do
    scope = Imagem.includes(arquivo_attachment: :blob)

    total = scope.count
    puts "Total de imagens: #{total}"

    scope.find_each.with_index(1) do |imagem, index|
      next unless imagem.arquivo.attached?

      ProcessUploadedImagemJob.perform_later(
        imagem.id,
        {
          protected_fields: [],
          sync_evento: true
        }
      )

      puts "[#{index}/#{total}] Enfileirada imagem ##{imagem.id}"
    end

    puts 'Backfill enfileirado.'
  end

  desc 'Reprocessa metadados apenas de imagens faltantes'
  task reprocessar_faltantes: :environment do
    scope = Imagem
      .includes(arquivo_attachment: :blob)
      .where(gps_location: '0.000000,0.000000')

    total = scope.count
    puts "Total de imagens a reprocessar: #{total}"

    scope.find_each.with_index(1) do |imagem, index|
      next unless imagem.arquivo.attached?

      ProcessUploadedImagemJob.perform_later(
        imagem.id,
        {
          protected_fields: [],
          sync_evento: true
        }
      )

      puts "[#{index}/#{total}] Enfileirada imagem ##{imagem.id}"
    end

    puts 'Reprocessamento enfileirado.'
  end
end
