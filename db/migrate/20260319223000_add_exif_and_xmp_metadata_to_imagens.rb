class AddExifAndXmpMetadataToImagens < ActiveRecord::Migration[7.1]
  def change
    add_column :imagens, :exif_metadata, :jsonb, default: {}, null: false
    add_column :imagens, :xmp_metadata, :jsonb, default: {}, null: false
  end
end
