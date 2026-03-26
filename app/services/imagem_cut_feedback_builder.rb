class ImagemCutFeedbackBuilder
  class << self
    def build(result)
      created_count = result.created_count.to_i
      counted_count = result.counted_count.to_i
      warning_count = result.warning_count.to_i
      error_count = result.error_count.to_i
      missing_count = [created_count - counted_count, 0].max

      message = "Corte concluído. #{created_count} tile(s) gerado(s)."
      message += " Contagem de cabeças em #{counted_count} de #{created_count} tile(s)."
      message += " #{missing_count} tile(s) sem contagem." if missing_count.positive?

      if warning_count.positive? || error_count.positive?
        details = []
        details << "avisos: #{warning_count}" if warning_count.positive?
        details << "falhas: #{error_count}" if error_count.positive?
        message += " (#{details.join(', ')})"
      end

      principal_reason = most_common_reason(result.message_counts)
      message += " Motivo principal: #{principal_reason}." if principal_reason.present?

      level = (warning_count.positive? || error_count.positive?) ? :alert : :notice

      {
        level: level,
        message: message
      }
    end

    private

    def most_common_reason(message_counts)
      return nil if message_counts.blank?

      message_counts.max_by { |_, count| count.to_i }&.first
    end
  end
end
