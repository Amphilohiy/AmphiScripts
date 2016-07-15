=begin
#======================================================================[LICENSE]
The MIT License (MIT)

Copyright (c) 2016 Amphilohiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#===============================================================================
=end

$imported ||= {}
$imported[:EventFactory] = "1.0.1"

#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  EVENT_FACTORY_TEMPLATES = [2]
  
  TAG_PRESERVE_POSITION = :save_pos
  TAG_REPLACE_EVENT = :replace
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
        
      def store_position(event)
        # look for more gentle solution
        #return if event.nil?
        if !event.parse_data[TAG_PRESERVE_POSITION].nil?
          @x = event.x
          @y = event.y
        end
      end
      
      def restore_position(event)
        # look for more gentle solution
        #return if event.nil?
        if !event.parse_data[TAG_PRESERVE_POSITION].nil? && !@x.nil? && !@y.nil?
          event.moveto(@x, @y)
        end
      end
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
#------------------------------------------------------------------------mapping
    # Проверить тему с пространством модуля
    Amphicore.serialize("event_factory_mapping", Hash)
    
    ORIGINALS_MAPPINGS = {}
    #well i thought lil registry would be nice
    @@last_map_id = nil
    @@last_map = nil
    
    def self.get_mapping(map_id)
      gather_mappings(map_id)
      $event_factory_mapping[map_id]
    end
    
    def self.get_original_mapping(map_id)
      gather_mappings(map_id)
      ORIGINALS_MAPPINGS[map_id]
    end
    
    def self.get_free(map_id)
      mapping = get_mapping(map_id)
      ia = 1
      while !mapping[ia].nil? do
        ia+=1
      end
      ia
    end
#--------------------------------------------------------------factory utilities    
    def self.get_map(map_id)
      if @@last_map_id != map_id
        @@last_map = if $game_map.map_id == map_id
          $game_map.instance_variable_get(:@map)
        else
          load_data(sprintf("Data/Map%03d.rvdata2", map_id))
        end
        @@last_map_id = map_id
      end
      @@last_map
    end
    
    def self.gather_mappings(map_id)
      cond2 = ORIGINALS_MAPPINGS[map_id].nil?
      cond1 = $event_factory_mapping[map_id].nil?
      return unless cond1 || cond2
      map = get_map(map_id)
      # create initial mapping
      if cond1
        mapping = {}
        $event_factory_mapping[map_id] = mapping
        map.events.each do |key, value| 
          data = Amphicore::TextParser.get_rgss_event(value)
          command = case
          when !data[TAG_REPLACE_EVENT].nil?
            CommandReplace.new(
              map_id: map_id, id: key, name: data[TAG_REPLACE_EVENT], x: value.x, y: value.y)
          else
            CommandNothing.new(id: key)
          end
          mapping[key] = command
        end
      end
      #collect origianl mapping
      if cond2
        mapping = []
        ORIGINALS_MAPPINGS[map_id] = mapping
        map.events.each do |key, value| 
          mapping.push(key) 
        end
      end
    end

    def self.get_scene
      scene = SceneManager.scene
      return scene if scene.class == Scene_Map
      SceneManager.instance_variable_get(:@stack).find do |scene|
        scene.class == Scene_Map
      end
    end
    
    def self.inject(command, map_id)
      return if $game_map.map_id != map_id
      $game_map.acef_stack.push(command)
      $game_map.acef_apply = true
    end
#----------------------------------------------------------------------interface   
    def self.create(map_id, name, x, y)
      free_id = get_free(map_id)
      mapping = get_mapping(map_id)
      command = CommandCreate.new(
        map_id: map_id, id: free_id, name: name, x: x, y: y)
      mapping[free_id] = command
      inject(command, map_id)
      free_id
    end
    
    def self.erase(map_id, event_id)
      mapping = get_mapping(map_id)
      command = CommandErase.new(
        map_id: map_id, id: event_id)
      inject(command, map_id)
      #check if we actually need to store command
      original_mapping = get_original_mapping(map_id)
      if original_mapping.include?(event_id)
        mapping[event_id] = command
      else
        mapping.delete(event_id)
      end
      $game_self_switches.acef_remove_path(map_id, event_id)
    end
    
    def self.replace(map_id, event_id, name, x, y)
      mapping = get_mapping(map_id)
      command = CommandReplace.new(
        map_id: map_id, id: event_id, name: name, x: x, y: y)
      mapping[event_id] = command
      inject(command, map_id)
      $game_self_switches.acef_remove_path(map_id, event_id)
    end
  end
end
#===============================================================================
#                                                                      INTRUDION
#===============================================================================
#----------------------------------------------------------map events injections
class Game_Map
  attr_accessor :acef_stack
  attr_accessor :acef_apply
  
  alias setup_events_event_factory setup_events
  def setup_events(*args)
    @acef_stack = []
    @acef_apply = false
    setup_events_event_factory(*args)
    acef_apply_events
    # Рефрешится дважды, найти обход в будущем
    refresh_tile_events
  end
  
  alias acef_setup setup
  def setup(*args)
    acef_store_position
    acef_setup(*args)
    acef_restore_position
  end
  
  def acef_store_position
    return if @map.nil?
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.store_position(@events[id])
    end
  end
  
  def acef_restore_position
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.restore_position(@events[id])
    end
  end
  
  def acef_apply_events
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.apply(@events)
    end
  end
  
  alias acef_update_events update_events
  def update_events
    acef_update_events
    acef_apply_current_events if @acef_apply
  end
  
  def acef_apply_current_events
    scene = Amphicore::EventFactory.get_scene
    spriteset = scene.instance_variable_get(:@spriteset)
    sprites = spriteset.instance_variable_get(:@character_sprites)
    viewport = spriteset.instance_variable_get(:@viewport1)
    @acef_stack.each do |command|
      command.apply_current(@events, sprites, viewport)
    end
    $game_map.refresh_tile_events
    @acef_apply = false
    @acef_stack.clear
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