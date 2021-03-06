class SyncVenue

  attr_reader :connection

  def initialize(connection: FoursquareConnection.new(api_version: '20160607', query:{verified: true}))
    @connection       = connection
  end
  
  def self.foursquare_summary(wdw_uri)
    fgv = FoursquareGuaranteedVenue.find_by_wdw_uri(wdw_uri)
    fr = FoursquareReview.where(venue_id: fgv.id).first_or_create
    fr.update(name: fgv.name, 
              searched_for: wdw_uri
    )
  end
  
  def self.venue(v_id)
    fgv                   = FoursquareGuaranteedVenue.venue(v_id) || FoursquareMissingVenue.new
    fr                    = FoursquareReview.where(venue_id: v_id).first_or_create
    venue_default_values  = FoursquareMissingVenue.new
    fr.update(name:           fgv.name,
              address:        fgv.location.fetch("formattedAddress", venue_default_values.formatted_address),
              lat:            fgv.location.fetch("lat", venue_default_values.lat),
              lng:            fgv.location.fetch("lng", venue_default_values.lng),
              categories:     [fgv.categories[0].fetch('name', venue_default_values.categories)],
              location:       fgv.location.to_s,
              canonical_url:  fgv.canonicalUrl.to_s,
              verified:       fgv.verified,
              dislike:        fgv.dislike,
              ok:             fgv.ok,
              rating:         fgv.rating || venue_default_values.rating,
              rating_color:   fgv.ratingColor || venue_default_values.rating_color,
              rating_signals: fgv.ratingSignals.to_s || venue_default_values.rating_signals,
              specials:       fgv.specials.to_s.to_s || venue_default_values.specials,
              wdw_uri:        fgv.url.split(/p*:/).last || venue_default_values.wdw_uri
    
              # searched_for: wdw_uri
    )
    
  end
  
  def self.all
    # updates reviews of all Foursquare Venues
    all_ids = self._collect_venue_ids
    responses = all_ids.each {|venue_id| self.venue(venue_id) }

  end

  def self.all_photos
    # update all venues and get venue ID's
    all_saved_venues = FoursquareReview.all.select(:venue_id)
    all_saved_venue_ids = all_saved_venues.collect {|review| review[:venue_id] }
    
    all_saved_venue_ids.each do |venue_id|
      self.photos(venue_id)
    end
  end

  def self.photos(venue_id)
    photos = FoursquareGuaranteedVenue.venue_photos(venue_id: venue_id)
    review = FoursquareReview.where(venue_id: venue_id).first_or_create
    photos.each do |photo|
      puts "parent venue: #{photo.foursquare_venue_id} photo id: #{photo.id}"
      fp = FoursquarePhoto.where(foursquare_photo_id: photo.id).first_or_create
      fp.update(source:                 photo.source.to_s,
                prefix:                 photo.prefix.to_s,
                suffix:                 photo.suffix.to_s,
                width:                  photo.width.to_i,
                height:                 photo.height.to_i,
                visibility:             photo.visibility.to_s,
                foursquare_user_id:     photo.user.fetch('id'),
                foursquare_venue_id:    venue_id,
                foursquare_photo_id:    photo.id,
                created_at:             Time.at(photo.createdAt.to_i),
                photographer_first_name:  photo.user.fetch("firstName", FoursquareMissingVenuePhoto.new.photographer_first_name),
                photographer_last_name:  photo.user.fetch("lastName", FoursquareMissingVenuePhoto.new.photographer_last_name)
      )
    end

  end

  def self.all_tips
    # update all venues and get venue ID's
    all_saved_venues = FoursquareReview.all.select(:venue_id)
    all_saved_venue_ids = all_saved_venues.collect {|review| review[:venue_id] }
    
    all_saved_venue_ids.each do |venue_id|
      self.tips(venue_id)
    end
  end

  def self.tips(venue_id)
    tips = FoursquareGuaranteedVenue.venue_tips(venue_id: venue_id, search_term: '')
    review = FoursquareReview.where(venue_id: venue_id).first_or_create
    puts "Tips available #{tips.count}"
    total_tips = 0
    tips.each do |tip|
      puts "parent venue: #{tip.foursquare_review_id} tip id: #{tip.id}"
      total_tips += 1
      # puts "Tips fufilled #{total_tips}/#{tips.count}" # possible division by zero

      ft  = FoursquareTip.where(foursquare_id: tip.id).first_or_create
      ft.update(
                venue_id:       venue_id.to_s,
                foursquare_id:  tip.id.to_s,
                text:           tip.text.to_s,
                tip_kind:       tip.type.to_s,
                canonical_url:  tip.canonicalUrl.to_s,
                lang:           tip.lang.to_s,
                likes:          tip.likes.to_s,
                agree_count:    tip.agreeCount,
                disagree_count: tip.disagreeCount,
                foursquare_author_id: tip.user.id,
                author_first_name: tip.user.firstName,
                author_last_name: tip.user.lastName,
                author_gender: tip.user.gender,
                author_photo_prefix: tip.user.photo.fetch("prefix"),
                author_photo_suffix: tip.user.photo.fetch("suffix", "")
      )
    end

  end

# -------------------
  def self._collect_venue_ids
    search_terms_list   = _collect_uris_and_search_terms
    venue_ids           = search_terms_list.collect {|search_term| FoursquareGuaranteedVenue.find_by_wdw_uri(search_term).id}
    nogos_arrays_list   = venue_ids.zip(search_terms_list).select {|vi| vi.first == "none"}
    corrected_nogos_ids = _correct_nogos_and_return_ids(nogos_arrays_list)

    sorted              = venue_ids.sort
    sorted.pop(corrected_nogos_ids.length)
    all_ids = [sorted, corrected_nogos_ids].flatten
    # remove id's that are of a foursquare_missing_venue #patch
    all_ids = all_ids.reject {|i| i == "none"}

  end
  
  
  def self._collect_uris_and_search_terms
    broken_search_terms = ["swandolphin.com", 
        "shadesofgreen.org", 
        "disneyworld.disney.go.com/resorts/board-walk-villas/"
      ]
    fixed_search_terms  = ["Walt Disney World Swan Hotel", 
        "Shades Of Green Resort",
        "disneys-boardwalk-villas"
      ]
    wdw_uris            = _wdw_uris.grep_v(Regexp.union(broken_search_terms))
    improved_wdw_uris   = (wdw_uris << fixed_search_terms).flatten
    improved_wdw_uris#.values_at(0..1)
  end
  
  def self._correct_nogos_and_return_ids(nogos_arrays_list)
    nogo_paths_list = nogos_arrays_list.collect {|nogo_array| _get_path_of_uri(nogo_array) }
    corrected_nogos = nogo_paths_list.collect {|nogo_path|
       FoursquareGuaranteedVenue.search_by_wdw_uri(nogo_path).select {|venue|
         venue.verified == true
       }.first
    }
    # compacting is just an temporary patch
    # hotels like possibly copper creek are omitted
    # venue.verified sometimes returns nil

    flattened_corrected_nogos = corrected_nogos.flatten.compact
    ids = flattened_corrected_nogos.map {|venue| venue.id}
        
  end
  
  def self._get_path_of_uri(nogo_array)
    nogo_array.last.split('/').last
  end
  
  def self._wdw_uris
    ## this should be investigated to  see if using seed datga is correct
    tp_seed_data = TouringPlansHotelImport.new.seed_data
    uris = tp_seed_data.collect {|seed| seed[:wdw_uri]}
  end
end