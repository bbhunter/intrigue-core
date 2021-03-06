module Intrigue
module Task
module Enrich
class NetBlock < Intrigue::Task::BaseTask

  include Intrigue::Task::Whois

  def self.metadata
    {
      :name => "enrich/net_block",
      :pretty_name => "Enrich NetBlock",
      :authors => ["jcran"],
      :description => "Fills in details for a NetBlock",
      :references => [],
      :type => "enrichment",
      :passive => true,
      :allowed_types => ["NetBlock"],
      :example_entities => [{"type" => "NetBlock", "details" => {"name" => "10.0.0.0/24"}}],
      :allowed_options => [],
      :created_types => []
    }
  end

  def run

    netblock_string = _get_entity_name
    lookup_string = _get_entity_name.split("/").first

    if _get_entity_detail "whois_full_text" # skip lookup if we already have it
      _log "Skipping lookup, we already have the details"
      out = @entity.details
    else # do the lookup
      out = whois(lookup_string) || {}
      # make sure not to overwrite the name in the details
      out = out.merge({"name" => netblock_string, "_hidden_name" => netblock_string})
      # lazy but easier than setting invidually
      _log "Setting entity details to... #{out}"
      _set_entity_details out
    end

    # check transferred
    if out["whois_full_text"] =~ /Early Registrations, Transferred to/
      _set_entity_detail "transferred", true
    end

    # check ipv6
    if _get_entity_name =~ /::/
      _set_entity_detail "ipv6", true
    end

    ###
    ### Determine if SCOPED!!!
    ###

    # Check new entities that we've scoped
    scoped_entity_types = [
      "Intrigue::Entity::Organization",
      "Intrigue::Entity::DnsRecord",
      "Intrigue::Entity::Domain" ]

    # check seeds
    if @entity.project.seeds
      @entity.project.seeds.each do |s|
        next unless scoped_entity_types.include? s["type"]
        if out["whois_full_text"] =~ /#{Regexp.escape(s["name"])}/
          _log "Marking as scoped: SEED ENTITY NAME MATCHED TEXT: #{s["name"]}}"
          @entity.scoped = true
          @entity.save
          return
        end
      end
    end

    # Check new entities that we've scoped in
    @entity.project.entities.where(:scoped => true, :type => scoped_entity_types ).each do |e|

      # make sure we skip any dns entries that are not fqdns. this will prevent
      # auto-scoping on a single name like "log" or even a number like "1"
      next if (e.type == "DnsRecord" || e.type == "Domain") && e.name.split(".").count == 1

      if out["whois_full_text"] =~ /#{Regexp.escape(e.name)}/
        _log "Marking as scoped: PROJECT ENTITY MATCHED TEXT: #{e.type}##{e.name}"
        @entity.scoped = true
        @entity.save
        return
      end

    end

    if @entity.created_by?("search_bgp")
      _log "Marking as scoped: CREATED BY SEARCH_BGP"
      @entity.scoped = true
      @entity.save
    end

  end

end
end
end
end