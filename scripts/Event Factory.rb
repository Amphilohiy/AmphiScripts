$imported ||= {}
$imported[:EventFactory] = "1.0.0"

#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  EVENT_FACTORY_TEMPLATES = [2]
#===============================================================================
#                                                                  EVENT FACTORY
#===============================================================================
  module EventFactory
#---------------------------------------------------------------template factory
    @@templates = {}
    
    
    # use as initialisation
    def self.add_template(map_id)
      map = load_data(sprintf("Data/Map%03d.rvdata2", map_id))
      map.events.each{ |id, event| @@templates[event.name] = event }
    end
    
    EVENT_FACTORY_TEMPLATES.each{ |map_id| add_template(map_id) }
#----------------------------------------------------------------command pattern   
    class Command
      # освежить в памяти разницу include и extend
      attr_reader :opts
      include EventFactory
      def initialize(opts = {})
        @opts = opts
        @opts.each do |key, value|
          instance_variable_set(("@"+key.to_s).to_sym, value)
        end
      end
      def apply(events) nil end
      def apply_current(events, sprites, viewport = nil) nil end
    end
    
    class CommandNothing < Command
    end
    
    class CommandCreate < Command
      def apply(events)
        event = @@templates[@name].clone.tap{|obj| obj.x = @x; obj.y = @y; obj.id = @id}
        events[@id] = Game_Event.new(@map_id, event)
        # is that correct?
        events[@id]
      end
      
      def apply_current(events, sprites, viewport = nil)
        event = apply(events)
        sprites.push(Sprite_Character.new(viewport, event))
      end
    end
    
    class CommandErase < Command
      def apply(events)
        events.delete(@id)
      end
      
      def apply_current(events, sprites, viewport = nil)
        apply(events)
        #keys = sprites.map.with_index {|value, key| key}
        sprites.reject! do |sprite| 
          result = sprite.character.id == @id
          sprite.dispose if result
          result
        end
      end
    end
    
    class CommandReplace < Command
      # Same as create
      def apply(events)
        event = @@templates[@name].clone.tap{|obj| obj.x = @x; obj.y = @y; obj.id = @id}
        events[@id] = Game_Event.new(@map_id, event)
        # is that correct?
        events[@id]
      end
      
      # Same as erase AND create
      def apply_current(events, sprites, viewport = nil)
        event = apply(events)
        #keys = sprites.map.with_index {|value, key| key}
        sprites.reject! do |sprite| 
          result = sprite.character.id == @id
          sprite.dispose if result
          result
        end
        sprites.push(Sprite_Character.new(viewport, event))
      end
    end
    
    FREE_COMMANDS = [CommandErase]
#------------------------------------------------------------------------mapping
    # Проверить тему с пространством модуля
    Amphicore.serialize("event_factory_mapping", Hash)
    
    def self.get_mapping(map_id)
      if $event_factory_mapping[map_id].nil?
        mapping = {}
        $event_factory_mapping[map_id] = mapping
        map = load_data(sprintf("Data/Map%03d.rvdata2", map_id))
        map.events.each do |key, value| 
          mapping[key] = CommandNothing.new(event_id: key)
        end
        mapping
      else
        $event_factory_mapping[map_id]
      end
    end
    
    def self.get_free(map_id)
      mapping = get_mapping(map_id)
      ia = 1
      while !mapping[ia].nil? || FREE_COMMANDS.include?(mapping[ia]) do
        ia+=1
      end
      ia
    end
#--------------------------------------------------------------factory utilities    
    def self.get_scene
      scene = SceneManager.scene
      return scene if scene.class == Scene_Map
      SceneManager.instance_variable_get(:@stack).find do |scene|
        scene.class == Scene_Map
      end
    end
    
    def self.inject(command, map_id)
      return if $game_map.map_id != map_id
      scene = get_scene
      spriteset = scene.instance_variable_get(:@spriteset)
      sprites = spriteset.instance_variable_get(:@character_sprites)
      viewport = spriteset.instance_variable_get(:@viewport1)
      events = $game_map.events
      command.apply_current(events, sprites, viewport)
      $game_map.refresh_tile_events
    end
#----------------------------------------------------------------------interface   
    def self.create(map_id, name, x, y)
      free_id = get_free(map_id)
      mapping = get_mapping(map_id)
      command = CommandCreate.new(
        map_id: map_id, id: free_id, name: name, x: x, y: y)
      mapping[free_id] = command
      inject(command, map_id)
    end
    
    def self.erase(map_id, event_id)
      mapping = get_mapping(map_id)
      command = CommandErase.new(
        map_id: map_id, id: event_id)
      mapping[event_id] = command
      inject(command, map_id)
      $game_self_switches.acef_remove_path(map_id, event_id)
    end
    
    def self.replace(map_id, event_id, name, x, y)
      mapping = get_mapping(map_id)
      command = CommandReplace.new(
        map_id: map_id, id: event_id, name: name, x: x, y: y)
      mapping[event_id] = command
      inject(command, map_id)
    end
  end
end
#===============================================================================
#                                                                      INTRUDION
#===============================================================================
#----------------------------------------------------------map events injections
class Game_Map
  alias setup_events_event_factory setup_events
  def setup_events(*args)
    setup_events_event_factory(*args)
    acef_cleanup
    acef_apply_events
    # Рефрешится дважды, найти обход в будущем
    refresh_tile_events
  end
  
  # Функция сбора лишних команд сейва. А надо ли?
  def acef_cleanup
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    keys = @events.keys
    work_keys = mapping.keys - keys
    work_keys = work_keys.select {|id| Amphicore::EventFactory::FREE_COMMANDS.include?(mapping[id].class)}
    work_keys.each {|id| mapping.delete(id)}
  end
  
  def acef_apply_events
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.apply(@events)
    end
  end
end
#----------------------------------------------------------------erase self data
[Game_SelfSwitches, Game_SelfVariables].each do |klass| 
  klass.class_exec do 
    alias acef_initialize initialize
    def initialize
      acef_initialize
      @acef_event_mapping = {}
    end
    
    def acef_store_path(key)
      return unless Array >= key.class && key.size >= 3
      event_id = "#{key[0]}-#{key[1]}".to_sym
      @acef_event_mapping[event_id] ||= []
      value = @acef_event_mapping[event_id]
      value.push(key) unless value.include?(key)
    end
    
    def acef_remove_path(map_id, event_id)
      acef_key = "#{map_id}-#{event_id}".to_sym
      keys = @acef_event_mapping[acef_key] || []
      keys.each do |key|
        @data.delete(key)
      end
      @acef_event_mapping.delete(acef_key)
    end
    
    alias acef_equal []=
    def []=(key, value)
      acef_store_path(key)
      acef_equal(key, value)
    end
  end 
end