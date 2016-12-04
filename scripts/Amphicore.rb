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
PATCHNOTE'S
► 1.0.0
  ♦ Text parser for ripping data from neutral text
    → Interface for parcing events, event's pages and items with notes
  ♦ Data Serialization
  ♦ Aliases for switches and variables
► 1.1.0
  ♦ Smart (not really) kwargs parser
  ♦ Text resolver
  ♦ Data Serialization
    → Fill missing data on savefile
  ♦ Text Parser
    → Diffirent caches for parsekits
#===============================================================================
=end
$imported ||= {}
$imported[:Amphicore] = "1.1.0"
#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  TEXT_NOTE_PARSER = ["<item>", "<\\+>", "<end>"]
  TEXT_EVENT_PARSER = ["<event>", "<\\+>", "<end>"]
  TEXT_EVENT_PAGE_PARSER = ["<page>", "<\\+>", "<end>"]
  
  TEXT_PARSER_CASE = 1
  
  TEXT_RESOLVER_DEFAULT_FONT = Font.new
#===============================================================================
#                                                                    TEXT PARSER
#===============================================================================
#---------------------------------------------------------------parsekit factory
  module TextParser
    # parse kit class, handlers included
    class ParseKit
      @@index = 0
      
      attr_reader :index
      attr_reader :token_start
      attr_reader :token_separator
      attr_reader :token_finish
      attr_reader :regex_case
      attr_reader :regex
      
      attr_reader :text_handlers
      def initialize(start, separator, finish, opts)
        @token_start = Regexp.new("#{start}", TEXT_PARSER_CASE)
        @token_separator = Regexp.new("#{separator}|\\z", TEXT_PARSER_CASE)
        @token_finish = Regexp.new("#{finish}", TEXT_PARSER_CASE)
        @regex_case = opts
        @index = @@index
        @text_handlers = {}
        @@index += 1
      end
      
      def handle_data(data)
        data.inject({}) do |result, value|
          k, v = value
          handler = @text_handlers[k]
          begin
            result[k] = handler.nil? ? v : handler.call(v)
          rescue Exception => e
            puts "Handler error: #{e}"
            puts "key:   #{k}"
            puts "value: #{v}"
            result[k] = v
          end
          result
        end
      end
      
      def add_handler key, &handler
        @text_handlers[key] = handler
      end
    end
    
    # template handlers
    PLAIN_PROC = proc do |value|
      eval("Proc.new do ||\n#{value}\nend")
    end
    
    # turn arguments to kit, that would be used later
    def self.create_parsekit(start, separator, finish, opts)
      ParseKit.new(start, separator, finish, opts)
    end
    
    # kit's that i personally use in my scripts (and implement some functionality(
    NOTE_PARSEKIT = create_parsekit(*TEXT_NOTE_PARSER, TEXT_PARSER_CASE)
    EVENT_PARSEKIT = create_parsekit(*TEXT_EVENT_PARSER, TEXT_PARSER_CASE)
    EVENT_PAGE_PARSEKIT = create_parsekit(*TEXT_EVENT_PAGE_PARSER, TEXT_PARSER_CASE)
#-------------------------------------------------------------------------parser
    # parser itself
    def self.parse_text(text, parsekit)
      tail = text
      data = {}
      # Searching for chunk
      while parsekit.token_start =~ tail do
        tail = $'
        chunk = tail
        if parsekit.token_finish =~ chunk then
          chunk = $`
        end
        # separate for data
        while parsekit.token_separator =~ chunk do
          chunk = $'
          /\s/ =~ $`.strip
          data[$`.to_sym] = $' if $` && $'
          if chunk.length == 0  then break end
        end
      end
      parsekit.handle_data data
    end
#---------------------------------------------------------------parser utilities 
    # collecting comments in event. Only starting comments counts
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
#----------------------------------------------------------------------interface    
    # common parsing with custom parsekit and memoization
    def self.get(item, text, parsekit)
      var_name = :"@apd#{parsekit.index}"
      result = item.instance_variable_get(var_name)
      if !result then
        result = parse_text(text, parsekit)
        item.instance_variable_set(var_name, result)
      end
      result
    end
    
    # parsing item with note (default <item> <+> <end>)
    def self.get_note(item)
      get(item, item.note, NOTE_PARSEKIT)
    end
    
    # get RPG::EVENT type of event
    def self.get_rgss_event(event)
      var_name = :"@apd#{EVENT_PARSEKIT.index}"
      result = event.instance_variable_get(var_name)
      return result unless result.nil?
      
      result = {}
      event.pages.reverse.each do |page|
        comments = collect_comments(page.list)
        chunk = parse_text(comments, EVENT_PARSEKIT)
        result.merge!(chunk)
      end
      
      event.instance_variable_set(var_name, result)
      result
    end
    
    # get RPG::EVENT page type of event
    def self.get_rgss_event_page(page)
      var_name = :"@apd#{EVENT_PAGE_PARSEKIT.index}"
      result = page.instance_variable_get(var_name)
      return result unless result.nil?
      comments = collect_comments(page.list)
      result = parse_text(comments, EVENT_PAGE_PARSEKIT)
      page.instance_variable_set(var_name, result)
      result
    end
  end
#===============================================================================
#                                                                  TEXT_RESOLVER
#===============================================================================
  module TextResolver
    @@bitmap = Bitmap.new(1, 1)
    def self.resolve(text, width, font = Amphicore::TEXT_RESOLVER_DEFAULT_FONT)
      @@bitmap.font = font
      
      # Splitting manual newliners
      paragraphs = []
      while /\n/ =~ text
        paragraphs << $`
        text = $'
      end
      paragraphs << text
      
      # Splitting to lines
      lines = []
      paragraphs.each do |paragraph|
        words = paragraph.split(' ')
        line = words.shift
        words.each do |word|
          concated_line = line + " #{word}"
          if @@bitmap.text_size(concated_line).width <= width then
            line = concated_line
          else
            lines << line
            line = word
          end
        end
        lines << line
      end
      
      lines
    end
  end
#===============================================================================
#                                                                        KWARGED
#===============================================================================  
  module Kwarged
    # making kwargs resolver wrapper
    def arged *methods
      methods.each do |method_name|
        # no constant 4 you on this one... because
        func_name = ("unarged_" + method_name.to_s).to_sym
        meth = method method_name
        # aliasing done this way
        define_singleton_method func_name, meth
        # map named keys to their position
        key_to_pos = meth.parameters.each_with_object({}).each_with_index do |pack, idx|
          result = pack.pop
          type, arg = pack.pop
          result[arg] = idx unless type == :rest
          result
        end
        # kwargs resolver
        anon = lambda{|*args|
          result = args.clone
          # check if we have kwargs last, and of course i can't tell if it's just hash
          kwargs = result[-1].is_a?(Hash) ? result.pop : {}
          # puts kwargs to their respective position
          kwargs.each do |key, value|
            result[key_to_pos[key]] = value
          end
          # just call with all arguments!
          send func_name, *result
        }
        # Deanon, haha
        define_singleton_method method_name, &anon
      end
    end
  end
#===============================================================================
#                                                                      UTILITIES
#=============================================================================== 
#------------------------------------------------------------------serialization
  # automatical svaing and loading
  SERIALIZED = {}
  
  def self.serialize(name, klass)
    SERIALIZED[name] = klass
  end
#------------------------------------------------------------------version check  
  # this should be final from the begginig btw. I hope it works.
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
    # inject serialisation
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
        content = contents[name.to_sym]
        # Make null data if there is no in savedata
        content = klass.new if content.nil?
        eval("$#{name} = content")
      end
    end
  end
end
#-----------------------------------------------------------------self variables
# analog of Game_SelfSwitches
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
#---------------------------------------------------------------events interface
class Game_Event
  # interface to get data of event
  def parse_data
    Amphicore::TextParser.get_rgss_event(@event)
  end
  # interface to get data of event's page
  def parse_page(page = @page)
    Amphicore::TextParser.get_rgss_event_page(page)
  end
end

class Game_CommonEvent
  # -//-
  def parse_data
    Amphicore::TextParser.get_rgss_event_page(@event)
  end
  # -//-
  def parse_page
    parse_data
  end
end

class Game_Troop < Game_Unit
  # -//-
  def parse_data
    Amphicore::TextParser.get_rgss_event(troop)
  end
  # -//-
  def parse_page(page_num)
    page = troop.pages[page_num]
    Amphicore::TextParser.get_rgss_event_page(page)
  end
end
#===============================================================================
#                                                                 INITIALIZATION
#===============================================================================
# aliases for standard $game_...
def var() $game_variables end
def swi() $game_switches end
def sswi() $game_self_switches end
# and not so standard...
def svar() $game_self_variables end

# some custom serialisations
Amphicore.serialize("game_hash", Hash)
Amphicore.serialize("game_self_variables", Game_SelfVariables)