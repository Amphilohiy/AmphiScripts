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
  ♦ Custom conditions (for events only ‼)
    → Forced custom conditions
#===============================================================================
=end
$imported ||= {}
$imported[:EventControls] = "1.0.0"
if $imported[:Amphicore].nil? then 
  raise "Import Amphicore script!"
end
#===============================================================================
#                                                                    CONFIG CORE
#===============================================================================
module Amphicore
  TAG_IGNORE_ORIGINAL_CONDITION = :ignore_cond
  TAG_CONDITION = :cond
  TAG_FORCE_CONDITION = :force
end
#===============================================================================
#                                                                      INTRUDION
#===============================================================================
class Game_Event
  alias acec_initialize initialize
  def initialize(map_id, event)
    acec_make_cond_pages(event)
    acec_initialize(map_id, event)
  end
  
  # create procs from data (cond & force)
  def acec_make_cond_pages(event)
    # should be there only for simple use of "parse_page" instead of Amphicore::TextParser.get_rgss_event_page(page)
    @event = event
    
    # proc storages
    @forced_pages = {}
    @cond_pages = {}
    
    event.pages.each_with_index do |_, index|
      data = parse_page(index)
      
      # custom tags, yay!
      fcond = data[Amphicore::TAG_FORCE_CONDITION]
      cond = data[Amphicore::TAG_CONDITION]
      
      # creation
      if fcond
        @forced_pages[index] = eval("Proc.new do ||\n#{fcond}\nend")
      end
      
      if cond
        @cond_pages[index] = eval("Proc.new do ||\n#{cond}\nend")
      end
    end
  end
  
  alias acec_refresh refresh
  def refresh
    # container for refreshable conditions (standard and cond), contains Boolean
    @fresh_conds = {}
    acec_refresh
  end
  
  alias acec_conditions_met? conditions_met? 
  def conditions_met?(page)
    result = true
    
    # it's passing event's, but it really easier for me to use indexes
    # but maybe i should reconsider use pages as keys instead
    page_num = @event.pages.index(page)
    
    # getting and checking conditions
    fcond = @forced_pages[page_num]
    fresh_cond = acec_fresh_cond(page_num)
    
    result &&= fresh_cond
    result &&= fcond.call unless fcond.nil?
    result
  end
  
  #the ones that updates by refresh
  def acec_fresh_cond(page_num)
    # memoization FTW! Force tag complicates things, so i intentionaly made room for slower conditions
    return @fresh_conds[page_num] unless @fresh_conds[page_num].nil?
    
    data = parse_page(page_num)
    # check cond tag
    cond = @cond_pages[page_num].nil? ? true : @cond_pages[page_num].call 
    # if page ignores originals, then it's true all way sunday
    # if not, then evaluate it
    orig = data[Amphicore::TAG_IGNORE_ORIGINAL_CONDITION] ? true : 
      acec_conditions_met?(@event.pages[page_num])
    result = cond && orig
    @fresh_conds[page_num] = result
    result
  end
  
  alias acec_update update
  def update
    acec_force_condition_update
    acec_update
  end
  
  # on every update check force condition
  def acec_force_condition_update
    # well, this one iteration got me thinking
    
    #new_page = @event.pages.map.with_index{|v, k|[v, k]}.reverse.find do |_, page_num|
    new_page = @event.pages.each_with_index.reverse_each.find do |_, page_num|
      fresh_cond = acec_fresh_cond(page_num)
      forced_cond = @forced_pages[page_num]
      forced_cond = forced_cond.nil? ? true : forced_cond.call
      fresh_cond && forced_cond
    end[0]
    
    if !new_page.nil? && new_page != @page
      setup_page(new_page)
      return
    end
  end
end