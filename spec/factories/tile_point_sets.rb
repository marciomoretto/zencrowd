FactoryBot.define do
  factory :tile_point_set do
    association :tile, factory: :tile
    axis { 'image' }
    points do
      [
        { id: 1, x: 10.5, y: 20.25 },
        { id: 2, x: 30.0, y: 40.75 }
      ]
    end
  end
end
