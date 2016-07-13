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
$imported[:Amphicore] = "1.0.0"
#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  TEXT_NOTE_PARSER = ["<item>", "<\\+>", "<end>"]
  TEXT_EVENT_PARSER = ["<event>", "<\\+>", "<end>"]
  TEXT_EVENT_PAGE_PARSER = ["<page>", "<\\+>", "<end>"]
  
  TEXT_PARSER_CASE = 1
#===============================================================================
#                                                                    TEXT PARSER
#===============================================================================
  module TextParser
#---------------------------------------------------------------parsekit factory
    def self.create_parsekit(start, separator, finish, opts)
      [
        Regexp.new("#{start}", TEXT_PARSER_CASE),
        Regexp.new("#{separator}|\\z", TEXT_PARSER_CASE),
        Regexp.new("#{finish}", TEXT_PARSER_CASE),
      ]
    end
    
    NOTE_PARSEKIT = create_parsekit(*TEXT_NOTE_PARSER, TEXT_PARSER_CASE)
    EVENT_PARSEKIT = create_parsekit(*TEXT_EVENT_PARSER, TEXT_PARSER_CASE)
    EVENT_PAGE_PARSEKIT = create_parsekit(*TEXT_EVENT_PAGE_PARSER, TEXT_PARSER_CASE)
#-------------------------------------------------------------------------parser
    def self.parse_text(text, parsekit)
      tail = text
      data = {}
      # Searching for chunk
      while parsekit[0] =~ tail do
        tail = $'
        chunk = tail
        if parsekit[2] =~ chunk then
          chunk = $`
        end
        # separate for data
        while parsekit[1] =~ chunk do
          chunk = $'
          /\s/ =~ $`.strip
          data[$`.to_sym] = $' if $` && $'
          if chunk.length == 0  then break end
        end
      end
      data
    end
#----------------------------------------------------------------------interface    
    def self.get(item, text, parsekit)
      result = item.instance_variable_get(:@apd)
      if !result then
        result = parse_text(text, parsekit)
        item.instance_variable_set(:@apd, result)
      end
      result
    end
    
    def self.get_note(item)
      get(item, item.note, NOTE_PARSEKIT)
    end
    
    def self.get_event(event)
      get_rgss_event(event.instance_variable_get(:@event))
    end
#---------------------------------------------------------------parser utilities    
    COMMENTS_COMMAND = [108, 408]
    def self.collect_comments(list)
      comments = []
      ia = 0
      while COMMENTS_COMMAND.include?(list[ia].code)  do
        comments.push(list[ia].parameters[0])
        ia += 1
      end
      comments.join("\n")
    end
    
    def self.get_rgss_event(event)
      result = event.instance_variable_get(:@apd)
      return result unless result.nil?
      
      result = {}
      event.pages.reverse.each do |page|
        comments = collect_comments(page.list)
        chunk = parse_text(comments, EVENT_PARSEKIT)
        result.merge!(chunk)
      end
      
      event.instance_variable_set(:@apd, result)
      result
    end
    
    def self.get_rgss_event_page
    end
  end
#===============================================================================
#                                                                      UTILITIES
#=============================================================================== 
#------------------------------------------------------------------serialization
  SERIALIZED = {}
  
  def self.serialize(name, klass)
    SERIALIZED[name] = klass
  end
#------------------------------------------------------------------version check  
  def self.check_version(imported, requred)
    /(\d+).(\d+).(\d+)(\w*)/ =~ imported
    imported = [$1.to_i, $2.to_i, $3.to_i, $4]
    /(\d+).(\d+).(\d+)(\w*)/ =~ requred
    requred = [$1.to_i, $2.to_i, $3.to_i, $4]
    4.times do |ia|
      return false if imported[ia] < requred[ia]
    end
    true
  end
end
#===============================================================================
#                                                                      INTRUDION
#===============================================================================
#-------------------------------------------------------------------data manager
module DataManager
  class << self
    alias create_game_objects_amphicore create_game_objects
    def create_game_objects(*args)
      create_game_objects_amphicore(*args)
      Amphicore::SERIALIZED.each do |name, klass|
        eval("$#{name} = #{klass.name}.new")
      end
    end
    
    alias make_save_contents_amphicore make_save_contents
    def make_save_contents(*args)
      contents = make_save_contents_amphicore(*args)
      Amphicore::SERIALIZED.each do |name, klass|
        contents[name.to_sym] = eval("$#{name}")
      end
      contents
    end

    alias extract_save_contents_amphicore extract_save_contents
    def extract_save_contents(contents)
      extract_save_contents_amphicore(contents)
      Amphicore::SERIALIZED.each do |name, klass|
        eval("$#{name} = contents[name.to_sym]")
      end
    end
  end
end
#-----------------------------------------------------------------self variables
class Game_SelfVariables
  def initialize
    @data = {}
  end
  def [](key)
    @data[variable_id] || 0
  end
  def []=(key, value)
    @data[key] = value
    on_change
  end
  def on_change
    $game_map.need_refresh = true
  end
end
#===============================================================================
#                                                                 INITIALIZATION
#===============================================================================
def var() $game_variables end
def swi() $game_switches end
def sswi() $game_self_switches end
def svar() $game_self_variables end

Amphicore.serialize("game_hash", Hash)
Amphicore.serialize("game_self_variables", Game_SelfVariables)
