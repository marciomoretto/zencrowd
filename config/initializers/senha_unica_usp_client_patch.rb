# Fix callback_id format in authorize URL for USP OAuth.
module SenhaUnicaUSP
  class Client
    private

    def callback_id_suffix
      callback_id = resolved_callback_id.to_s.strip
      return '' if callback_id.empty?

      "&callback_id=#{callback_id}"
    end
  end
end
