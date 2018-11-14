=begin
#======================================================================[LICENSE]
The MIT License (MIT)

Copyright (c) 2016-2018 Amphilohiy

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
PATCHNOTE'S
► 1.0.0
  ♦ Template system
  ♦ Create, erase and replace events
    → Replace event on startup by tag
  ♦ Position preservation
♦ 1.0.1
  ♦ Arged interface
  ♦ Bugfixes
    → Cache clear bug fixed
    → Game map interpreter freeze bug fixed
♦ 1.0.2
  ♦ Bugfixes
    → Storing/restoring positions of deleted "original" events crash
#===============================================================================
=end
$imported ||= {}
$imported[:EventFactory] = "1.0.1"
if $imported[:Amphicore].nil? then 
  raise "Import Amphicore script!"
end
raise "Required at least Amphicore v1.1.0" unless Amphicore.check_version($imported[:Amphicore], "1.1.0")

#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  EVENT_FACTORY_TEMPLATES = []
  
  TAG_PRESERVE_POSITION = :save_pos
  TAG_REPLACE_EVENT = :replace
#===============================================================================
#                                                                  EVENT FACTORY
#===============================================================================
  module EventFactory
    extend Amphicore::Kwarged
#---------------------------------------------------------------template factory
    # all template events goes here (name => event)
    @@templates = {}
    
    # use as initialisation
    def self.add_template(map_id)
      map = load_data(sprintf("Data/Map%03d.rvdata2", map_id))
      map.events.each{ |id, event| @@templates[event.name] = event }
    end
    
    EVENT_FACTORY_TEMPLATES.each{ |map_id| add_template(map_id) }
#----------------------------------------------------------------command pattern   
    # if not sure what command is - google patterns. Whole concept goes around
    # hash with commands, which represents difference between original map, and
    # result of developer maniputations
    class Command
      attr_reader :opts
      include EventFactory
      # some... really... weird initialization... i think i wanted to experiment
      # a little bit
      def initialize(opts = {})
        @opts = opts
        @opts.each do |key, value|
          instance_variable_set(("@"+key.to_s).to_sym, value)
        end
      end
      # calls for applying difference on startings map
      def apply(events) nil end
      # calls for applying difference on current map
      def apply_current(events, sprites, viewport = nil) nil end
        
      def store_position(event)
        # look for more gentle solution
        # return if event.nil?
        if !event.parse_data[TAG_PRESERVE_POSITION].nil?
          @x = event.x
          @y = event.y
        end
      end
      
      def restore_position(event)
        # look for more gentle solution
        # return if event.nil?
        if !event.parse_data[TAG_PRESERVE_POSITION].nil? && !@x.nil? && !@y.nil?
          event.moveto(@x, @y)
        end
      end
    end
    
    # a placeholder for... well... doing nothing, just to keep track of original
    # event's (like looking for free id... only for looking for free id)
    class CommandNothing < Command
    end
    
    # creating!
    class CommandCreate < Command
      def apply(events)
        event = @@templates[@name].clone.tap{|obj| obj.x = @x; obj.y = @y; obj.id = @id}
        events[@id] = Game_Event.new(@map_id, event)
        # is that correct?
        events[@id]
      end
      
      # creating sprite in middle of game got me thinking.
      def apply_current(events, sprites, viewport = nil)
        event = apply(events)
        sprites.push(Sprite_Character.new(viewport, event))
      end
    end
    
    # DESTROYING MORTAL EVENTS FOR GOD OF DESTRUCTION!
    class CommandErase < Command
      def apply(events)
        events.delete(@id)
      end
      
      def apply_current(events, sprites, viewport = nil)
        apply(events)
        #keys = sprites.map.with_index {|value, key| key}
        # well, creating sprite was interesting, but tracking and disposing existed...
        # btw sprite would be destroyed with delay by gc
        sprites.reject! do |sprite| 
          result = sprite.character.id == @id
          sprite.dispose if result
          result
        end
        # if you want destroy current event i should clear interpreter
        # otherwise i could freeze everyone... forever!
        $game_map.interpreter.clear if $game_map.interpreter.event_id == @id
      end
    end
    
    class CommandReplace < Command
      # Same as create (exept positioning)
      def apply(events)
        # desiding position
        old_event = events[@id]
        x = @x || old_event.x
        y = @y || old_event.y
        # setting event
        event = @@templates[@name].clone.tap{|obj| obj.x = x; obj.y = y; obj.id = @id}
        events[@id] = Game_Event.new(@map_id, event)
        # is that correct?
        events[@id]
      end
      
      # Same as erase AND create
      def apply_current(events, sprites, viewport = nil)
        event = apply(events)
        #keys = sprites.map.with_index {|value, key| key}
        # @TODO find first and replace with new
        sprites.reject! do |sprite| 
          result = sprite.character.id == @id
          sprite.dispose if result
          result
        end
        sprites.push(Sprite_Character.new(viewport, event))
        
        $game_map.interpreter.clear if $game_map.interpreter.event_id == @id
      end
    end
#------------------------------------------------------------------------mapping
    # check module bindings
    Amphicore.serialize("event_factory_mapping", Hash)
    
    ORIGINALS_MAPPINGS = {}
    # well i thought lil registry would be nice (made a little bit faster)
    @@last_map_id = nil
    @@last_map = nil
    
    # mapping is that difference hash that i told about near command section
    def self.get_mapping(map_id)
      gather_mappings(map_id)
      $event_factory_mapping[map_id]
    end
    
    # mapping of original id's
    def self.get_original_mapping(map_id)
      gather_mappings(map_id)
      ORIGINALS_MAPPINGS[map_id]
    end
    
    # searching for free id (used only for creation)
    def self.get_free(map_id)
      mapping = get_mapping(map_id)
      ia = 1
      while !mapping[ia].nil? do
        ia+=1
      end
      ia
    end
#--------------------------------------------------------------factory utilities    
    # yep, gets map (using registry of maps ofc)
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
    
    # get 2 mappgins - differece and original. First goes to save, second memoized for game session
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

    # tricky one - scene ripped from SceneManager
    def self.get_scene
      scene = SceneManager.scene
      return scene if scene.class == Scene_Map
      SceneManager.instance_variable_get(:@stack).find do |scene|
        scene.class == Scene_Map
      end
    end
    
    # put for current map an order to handle events
    def self.inject(command, map_id)
      return if $game_map.map_id != map_id
      $game_map.acef_stack.push(command)
      $game_map.acef_apply = true
    end
    
    # clear caches
    def self.clear_caches
      @@last_map_id = nil
      @@last_map = nil
      ORIGINALS_MAPPINGS.clear
    end
#----------------------------------------------------------------------interface   
    def self.create(name, x, y, map_id = $game_map.map_id)
      free_id = get_free(map_id)
      mapping = get_mapping(map_id)
      command = CommandCreate.new(
        map_id: map_id, id: free_id, name: name, x: x, y: y)
      mapping[free_id] = command
      inject(command, map_id)
      free_id
    end
    
    def self.erase(event_id, map_id = $game_map.map_id)
      mapping = get_mapping(map_id)
      command = CommandErase.new(
        map_id: map_id, id: event_id)
      inject(command, map_id)
      original_mapping = get_original_mapping(map_id)
      if original_mapping.include?(event_id)
        mapping[event_id] = command
      else
        mapping.delete(event_id)
      end
      $game_self_switches.acef_remove_path(map_id, event_id)
    end
    
    def self.replace(event_id, name, x = nil, y = nil, map_id = $game_map.map_id)
      mapping = get_mapping(map_id)
      command = CommandReplace.new(
        map_id: map_id, id: event_id, name: name, x: x, y: y)
      mapping[event_id] = command
      inject(command, map_id)
      $game_self_switches.acef_remove_path(map_id, event_id)
    end
    
    arged :create, :erase, :replace
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
    # we need to store commands (explain later)
    @acef_stack = []
    @acef_apply = false
    setup_events_event_factory(*args)
    # inject mapping
    acef_apply_events
    # refreshes twice, find workaround later (saving alias)
    refresh_tile_events
  end
  
  alias acef_setup setup
  def setup(*args)
    # save_pos injection
    acef_store_position
    acef_setup(*args)
    acef_restore_position
  end
  
  def acef_store_position
    return if @map.nil?
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.store_position(@events[id]) if @events.has_key? id
    end
  end
  
  def acef_restore_position
    mapping = Amphicore::EventFactory.get_mapping(@map_id)
    mapping.each do |id, event|
      event.restore_position(@events[id]) if @events.has_key? id
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
    # apply command AFTER update for a reason - while updating @events hash is
    # occupied (i.e. frozen) so it throws an exception if i try to manipulate it.
    # So i store command and applying it later, after iteration
    acef_apply_current_events if @acef_apply
  end
  
  # looksd scary, but mostly it's aquiring required objects
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
# same injection for 2 classes. Neat, huh?
# self switches and self variables now tracks what keys have event, so
# i can delete those values without iteration through whole hash
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

#-----------------------------------------------------------------some interface
class Game_Interpreter
  def create_event(*args)
    Amphicore::EventFactory.create(*args)
  end
  
  def erase_event(*args)
    Amphicore::EventFactory.erase(*args)
  end
  
  def replace_event(*args)
    Amphicore::EventFactory.replace(*args)
  end
end

# for route script interpreting
class Game_Event
  def create_event(*args)
    Amphicore::EventFactory.create(*args)
  end
  
  def erase_event(*args)
    Amphicore::EventFactory.erase(*args)
  end
  
  def replace_event(*args)
    Amphicore::EventFactory.replace(*args)
  end
end
#--------------------------------------------------------------------cache clear
module DataManager
  class << self
    alias acef_create_game_objects create_game_objects
    def create_game_objects(*args)
      Amphicore::EventFactory.clear_caches
      acef_create_game_objects(*args)
    end

    alias acef_extract_save_contents extract_save_contents
    def extract_save_contents(contents)
      Amphicore::EventFactory.clear_caches
      acef_extract_save_contents(contents)
    end
  end
end