class Hotel < ActiveRecord::Base
  has_many :cached_flickr_photos

  def tips
    # "tipe sher"
    # self.foursquare_venue_id
    # self.foursquare_review
    FoursquareReview.find_by(venue_id: self.foursquare_venue_id).tips
    # self.foursquare_review.tips
  end

  def foursquare_photos
    # "pavlova"
    self.foursquare_review_by_venue_id.photos
  end

  def foursquare_review_by_venue_id
    FoursquareReview.find_by(venue_id: self.foursquare_venue_id) #|| FoursquareMissingVenue.new
  end
  
  def self.geojson
    hotels = Array(Hotel.all)
    @geojson = Array.new
#
    hotels.each do |hotel|
      @coordinates = hotel.foursquare_review_by_venue_id
      @geojson << {
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [@coordinates.lng, @coordinates.lat]
        },
        properties: {
          id: hotel.id,
          name: hotel.name,
          address: hotel.address,
          :'marker-color' => '#00607d',
          :'marker-symbol' => 'circle',
          :'marker-size' => 'medium'
        }
      }
    end
    results = @geojson

  end
end
