##
# * Name: App
# * Description: Experimental Application class
# * Author: rkumar (arunachalesha)
# * Heavily modified by @chrisarcand
# * file created 2010-09-04 22:10

require 'logger'
require 'rbhex'
require 'rbhex/core/util/widgetshortcuts'

include RubyCurses
include RubyCurses::Utils
include Io

module RubyCurses
  extend self

  class Widget
    def changed *args, &block
      bind :CHANGED, *args, &block
    end
    def leave *args, &block
      bind :LEAVE, *args, &block
    end
    def enter *args, &block
      bind :ENTER, *args, &block
    end
    def click *args, &block
      bind :PRESS, *args, &block
    end
  end

  class CheckBox
    def text(*val)
      if val.empty?
        @value ? @onvalue : @offvalue
      else
        super
      end
    end
  end

  class App
  include RubyCurses::WidgetShortcuts
    attr_reader :config
    attr_reader :form
    attr_reader :window
    attr_writer :quit_key
    # the row on which to prompt user for any inputs
    #attr_accessor :prompt_row # 2011-10-17 14:06:22

    def initialize config={}, &block
      @config = config
      widget_shortcuts_init
      @variables = {}
      @current_object = []
      @_system_commands = %w{ bind_global bind_component field_help_text }

      init_vars
      $log.debug "XXX APP CONFIG: #{@config}  " if $log.debug?
      run &block
    end

    def init_vars
      @quit_key ||= FFI::NCurses::KEY_F10

      unless $ncurses_started
        init_ncurses
      end

      $lastline = Ncurses.LINES - 1

      unless $log
        path = File.join(ENV["LOGDIR"] || "./" ,"rbhex.log")
        file   = File.open(path, File::WRONLY|File::TRUNC|File::CREAT)
        $log = Logger.new(path)
        $log.level = Logger::DEBUG # change to warn when you've tested your app.
        colors = Ncurses.COLORS
        $log.debug "START #{colors} colors  --------- #{$0} win: #{@window} "
      end
    end

    def logger; return $log; end

    def close
      raw_message_destroy
      $log.debug " INSIDE CLOSE, #{@stop_ncurses_on_close} "
      @window.destroy if !@window.nil?
      $log.debug " INSIDE CLOSE, #{@stop_ncurses_on_close} "
      if @stop_ncurses_on_close
        $tt.destroy if $tt  # added on 2011-10-9 since we created a window, but only hid it after use
        VER::stop_ncurses
        $log.debug " CLOSING NCURSES"
      end
      $log.debug " CLOSING APP"
    end

    def loop &block
      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels
      @break_key = ?\C-q.getbyte(0)
      # added this extra loop since from some places we exit using throw :close
      # amd that was in a much higher place, and was getting us right out, with
      # no chance of user canceling quit. This extra loop allows us to remain
      # added on 2011-11-24
      while true
        catch :close do
          while((ch = @window.getchar()) != 999 )
            #break if ch == @break_key
            if ch == @break_key || ch == @quit_key
              #stopping = @window.fire_close_handler
              #break if stopping.nil? || stopping
              break
            end

            if @keyblock
              str = keycode_tos ch
              @keyblock.call(str.gsub(/-/, "_").to_sym) # not used ever
            end

            yield ch if block # <<<----
            # this is what the user should have control ove. earlier we would put this in
            # a try catch block so user could do what he wanted with the error. Now we
            # need to get it to him somehow, perhaps through a block or on_error event
            begin
              @form.handle_key ch
            rescue => err
              $log.debug( "handle_key rescue reached ")
              $log.debug( err.to_s)
              $log.debug(err.backtrace.join("\n"))
              textdialog [err.to_s, *err.backtrace], :title => "Exception"
            end
            #@form.repaint # was this duplicate ?? handle calls repaint not needed
            @window.wrefresh
          end
        end # catch
        stopping = @window.fire_close_handler
        @window.wrefresh
        break if stopping.nil? || stopping
      end # while
    end

    # if calling loop separately better to call this, since it will shut off ncurses
    # and print error on screen.
    def safe_loop &block
      begin
        loop &block
      rescue => ex
        $log.debug( "APP.rb rescue reached ")
        $log.debug( ex) if ex
        $log.debug(ex.backtrace.join("\n")) if ex
      ensure
        close
        # putting it here allows it to be printed on screen, otherwise it was not showing at all.
        if ex
          puts "========== EXCEPTION =========="
          p ex
          puts "==============================="
          puts(ex.backtrace.join("\n"))
        end
      end
    end

    # returns a symbol of the key pressed
    # e.g. :C_c for Ctrl-C
    # :Space, :bs, :M_d etc
    def keypress &block
     @keyblock = block
    end

    # updates a global var with text. Calling app has to set up a Variable with that name and attach to
    # a label so it can be printed.
    def message text
      $status_message.value = text # trying out 2011-10-9
      #@message.value = text # 2011-10-17 14:07:01
    end

    # during a process, when you wish to update status, since ordinarily the thread is busy
    # and form does not get control back, so the window won't refresh.
    # This will only update on keystroke since it uses statusline
    # @deprecated please use {#status_line} instead of a message label
    def message_immediate text
      $log.warn "DEPRECATED, use message(),  or rb_puts or use status_window"
      $status_message.value = text # trying out 2011-10-9 user needs to use in statusline command
      # 2011-10-17 knocking off label, should be printed on status_line
    end

    # Usage: application is inside a long processing loop and wishes to print ongoing status
    # NOTE: if you use this, you must use raw_message_destroy at some stage, after processing
    # or on_leave of object.
    # @deprecated Use say_with_pause or use rdialogs status_window, see test2.rb
    def raw_message text, config={}, &blk
      $raw_window ||= one_line_window last_line(), config, &blk
      width = $raw_window.width == 0 ? FFI::NCurses.COLS : $raw_window.width
      text = "%-*s" % [width, text]

      $raw_window.attron(Ncurses.COLOR_PAIR($normalcolor) )
      $raw_window.printstring 0,0,text, $normalcolor #, 'normal' if @title
      $raw_window.wrefresh
    end

    def raw_message_destroy
      if $raw_window
        $raw_window.destroy
        $raw_window = nil
      end
    end

    # shows a simple progress bar on last row, using stdscr
    # @param [Float, Array<Fixnum,Fixnum>] percentage, or part/total
    # If Array of two numbers is given then also print part/total on left of bar
    # @deprecated - don't use stdscr at all, use rdialogs status_window (see test2.rb)
    def raw_progress arg
      $log.warning "WARNING: don't use this method as it uses stdscr"
      row = @message_label ? @message_label.row : Ncurses.LINES-1
      s = nil
      case arg
      when Array
        #calculate percentage
        pc = (arg[0]*1.0)/arg[1]
        # print items/total also
        s = "%-10s" % "(#{arg[0]}/#{arg[1]})"
      when
        Float
        pc = arg
      end
      scr = Ncurses.stdscr
      endcol = Ncurses.COLS-1
      startcol = endcol - 12
      stext = ("=" * (pc*10).to_i)
      text = "[" + "%-10s" % stext + "]"
      Ncurses.mvprintw( row ,startcol-10, s) if s
      Ncurses.mvprintw row ,startcol, text
    end

    # used only by LiveConsole, if enables in an app, usually only during testing.
    def get_binding
      return binding()
    end

    # suspends curses so you can play around on the shell
    # or in cooked mode like Vim does. Expects a block to be passed.
    # Purpose: you can print some stuff without creating a window, or
    # just run shell commands without coming out.
    # NOTE: if you pass clear as true, then the screen will be cleared
    # and you can use puts or print to print. You may have to flush.
    # However, with clear as false, the screen will not be cleared. You
    # will have to print using printw, and if you expect user input
    # you must do a "system /bin/stty sane"
    # If you print stuff, you will have to put a getch() or system("read")
    # to pause the screen.
    def suspend clear=true
      return unless block_given?
      Ncurses.def_prog_mode
      if clear
        Ncurses.endwin
        # NOTE: avoid false since screen remains half off
        # too many issues
      else
        system "/bin/stty sane"
      end
      yield if block_given?
      Ncurses.reset_prog_mode
      if !clear
        # Hope we don't screw your terminal up with this constantly.
        VER::stop_ncurses
        VER::start_ncurses
        #@form.reset_all # not required
      end
      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels
    end

    def get_all_commands
      opts = @_system_commands.dup
      if respond_to? :get_commands
        opts.push(*get_commands())
      end
      opts
    end

    # bind a key to a method at global (form) level
    # Note that individual component may be overriding this.
    # FIXME: why are we using rawmessage and then getchar when ask would suffice
    def bind_global
      opts = get_all_commands
      cmd = rb_gets("Select a command (<tab> for choices) : ", opts)
      if cmd.nil? || cmd == ""
        rb_puts "Aborted."
        return
      end
      key = []
      str = ""
      #raw_message "Enter one or 2 keys. Finish with ENTER. Enter first key:"
      #ch = @window.getchar()
      #raw_message_destroy
      #if [KEY_ENTER, 10, 13, ?\C-g.getbyte(0)].include? ch
        #say_with_pause "Aborted."
        #return
      #end
      # the next is fine but does not allow user to enter a control or alt or function character
      # since it uses Field. It is fine if you want to force alphanum input
      ch = rb_getchar("Enter one or two keys. Finish with <ENTER>. Enter first key:")
      unless ch
        rb_puts "Aborted. <Press a key>"
        return
      end
      key << ch
      str << keycode_tos(ch)
      ch = rb_getchar  "Got #{str}. Enter second key or hit return:"
      unless ch
        rb_puts "Aborted. <Press a key>"
        return
      end
      if ch == KEY_ENTER || ch == 13
      else
        key << ch
        str << keycode_tos(ch)
      end
      if !key.empty?
        rb_puts "Binding #{cmd} to #{str}. "
        key = key[0] if key.size == 1
        #@form.bind_key(key, cmd.to_sym) # not finding it, getting called by that comp
        @form.bind_key(key){ send(cmd.to_sym) }
      end
    end

    def bind_component
      #rb_puts "Todo. ", :color_pair => get_color($promptcolor, :red, :black)
      print_error_message "Todo this. "
      # the idea here is to get the current component
      # and bind some keys to some methods.
      # however, how do we divine the methods we can map to
      # and also in some cases the components itself has multiple components
    end

    # displays help_text associated with field. 2011-10-15
    def field_help_text
      f = @form.get_current_field
      if f.respond_to?('help_text')
        h = f.help_text
        h = "No help text defined for this field.\nTry F1, or press '?' for key-bindings." unless h
        textdialog "#{h}", :title => "Widget Help Text"
      else
        alert "Could not get field #{f} or does not respond to helptext. Try F1 or '?'"
      end
    end

    # prompts user for a command. we need to get this back to the calling app
    # or have some block stuff TODO
    # Actually, this is naive, you would want to pass some values in like current data value
    # or lines ??
    # Also may want command completion, or help so all commands can be displayed
    # NOTE: This is gonna change very soon - 2012-01-8
    def get_command_from_user choices=["quit","help", "suspend", "shell_output"]
      @_command_history ||= Array.new
      str = rb_gets("Cmd: ", choices) { |q| q.default = @_previous_command; q.history = @_command_history }
              @_command_history << str unless @_command_history.include? str
      # shell the command
      if str =~ /^!/
        str = str[1..-1]
        suspend(false) {
          #system(str);
          $log.debug "XXX STR #{str}  " if $log.debug?

          output=`#{str}`
          system("echo ' ' ");
          $log.debug "XXX output #{output} " if $log.debug?
          system("echo '#{output}' ");
          system("echo Press Enter to continue.");
          system("read");
        }
        return nil # i think
      else
        # TODO
        # here's where we can take internal commands
        #alert "[#{str}] string did not match :!"
        str = str.to_s #= str[1..-1]
        cmdline = str.split
        cmd = cmdline.shift #.to_sym
        return unless cmd # added 2011-09-11 FFI
        f = @form.get_current_field
        if respond_to?(cmd, true)
          if cmd == "close"
            throw :close # other seg faults in del_panel window.destroy executes 2x
          else
            res = send cmd, *cmdline
          end
        elsif f.respond_to?(cmd, true)
          res = f.send(cmd, *cmdline)
        else
          alert "App: #{self.class} does not respond to #{cmd} "
          ret = false
          # what is this execute_this: some kind of general routine for all apps ?
          ret = execute_this(cmd, *cmdline) if respond_to?(:execute_this, true)
          rb_puts("#{self.class} does not respond to #{cmd} ", :color_pair => $promptcolor) unless ret
          # should be able to say in red as error
        end
      end
    end

    # @group methods to create widgets easily
    #
    # process arguments based on datatype, perhaps making configuration
    # of some components easier for caller avoiding too much boiler plate code
    #
    # create a field
    def OLDfield *args, &block
      config = {}
      events = [ :CHANGED,  :LEAVE, :ENTER, :CHANGE ]
      block_event = :CHANGED # LEAVE, ENTER, CHANGE

      _process_args args, config, block_event, events
      config.delete(:title)
      _position config
      # hope next line doesn't bonk anything
      config[:display_length] ||= @stack.last.width if @stack.last # added here not sure 2010-11-17 18:43
      field = Field.new @form, config
      # shooz uses CHANGED, which is equivalent to our CHANGE. Our CHANGED means modified and exited
      if block
        field.bind(block_event, &block)
      end
      return field
    end

    def OLDlabel *args
      events = block_event = nil
      config = {}
      _process_args args, config, block_event, events
      config[:text] ||= config[:name]
      config[:height] ||= 1
      config.delete(:title)
      _position(config)
      label = Label.new @form, config
      # shooz uses CHANGED, which is equivalent to our CHANGE. Our CHANGED means modified and exited
      return label
    end

    alias :text :label

    def OLDbutton *args, &block
      config = {}
      events = [ :PRESS,  :LEAVE, :ENTER ]
      block_event = :PRESS

      _process_args args, config, block_event, events
      config[:text] ||= config[:name]
      config.delete(:title)
      # flow gets precedence over stack
      _position(config)
      button = Button.new @form, config
      # shooz uses CHANGED, which is equivalent to our CHANGE. Our CHANGED means modified and exited
      if block
        button.bind(block_event, &block)
      end
      return button
    end

    # create a list
    # Since we are mouseless, one can traverse without selection. So we have a different
    # way of selecting row/s and traversal. XXX this aspect of LB's has always troubled me hugely.
    def OLDedit_list *args, &block  # earlier list_box
      config = {}
      # TODO confirm events
      # listdataevent has interval added and interval removed, due to multiple
      # selection, we have to make that simple for user here.
      events = [ :LEAVE, :ENTER, :ENTER_ROW, :LEAVE_ROW, :LIST_DATA_EVENT ]
      # TODO how to do this so he gets selected row easily
      block_event = :ENTER_ROW

      _process_args args, config, block_event, events
      # naive defaults, since list could be large or have very long items
      # usually user will provide
      if !config.has_key? :height
        ll = 0
        ll = config[:list].length + 2 if config.has_key? :list
        config[:height] ||= ll
        config[:height] = 15 if config[:height] > 20
      end
      if @current_object.empty?
        $log.debug "1 APP LB w: #{config[:width]} ,#{config[:name]} "
        config[:width] ||= @stack.last.width if @stack.last
        $log.debug "2 APP LB w: #{config[:width]} "
        config[:width] ||= longest_in_list(config[:list])+2
        $log.debug "3 APP LB w: #{config[:width]} "
      end
      # if no width given, expand to flows width XXX SHOULD BE NOT EXPAND ?
      #config[:width] ||= @stack.last.width if @stack.last
      #if config.has_key? :choose
      config[:default_values] = config.delete :choose
      # we make the default single unless specified
      config[:selection_mode] = :single unless config.has_key? :selection_mode
      if @current_object.empty?
      if @instack
        # most likely you won't have row and col. should we check or just go ahead
        col = @stack.last.margin
        config[:row] = @app_row
        config[:col] = col
        @app_row += config[:height] # this needs to take into account height of prev object
      end
      end
      useform = nil
      useform = @form if @current_object.empty?
      field = EditList.new useform, config # earlier ListBox
      # shooz uses CHANGED, which is equivalent to our CHANGE. Our CHANGED means modified and exited
      if block
        # this way you can't pass params to the block
        field.bind(block_event, &block)
      end
      return field
    end

    # toggle button
    def OLDtoggle *args, &block
      config = {}
      # TODO confirm events
      events = [ :PRESS,  :LEAVE, :ENTER ]
      block_event = :PRESS
      _process_args args, config, block_event, events
      config[:text] ||= longest_in_list2( [config[:onvalue], config[:offvalue]])
        #config[:onvalue] # needed for flow, we need a better way FIXME
      _position(config)
      toggle = ToggleButton.new @form, config
      if block
        toggle.bind(block_event, &block)
      end
      return toggle
    end

    # check button
    def OLDcheck *args, &block
      config = {}
      # TODO confirm events
      events = [ :PRESS,  :LEAVE, :ENTER ]
      block_event = :PRESS
      _process_args args, config, block_event, events
      _position(config)
      toggle = CheckBox.new @form, config
      if block
        toggle.bind(block_event, &block)
      end
      return toggle
    end

    # radio button
    def OLDradio *args, &block
      config = {}
      # TODO confirm events
      events = [ :PRESS,  :LEAVE, :ENTER ]
      block_event = :PRESS
      _process_args args, config, block_event, events
      a = config[:group]
      # FIXME we should check if user has set a varialbe in :variable.
      # we should create a variable, so he can use it if he wants.
      if @variables.has_key? a
        v = @variables[a]
      else
        v = Variable.new
        @variables[a] = v
      end
      config[:variable] = v
      config.delete(:group)
      _position(config)
      radio = RadioButton.new @form, config
      if block
        radio.bind(block_event, &block)
      end
      return radio
    end

    # editable text area
    def OLDtextarea *args, &block
      require 'rbhex/core/widgets/rtextarea'
      config = {}
      # TODO confirm events many more
      events = [ :CHANGE,  :LEAVE, :ENTER ]
      block_event = events[0]
      _process_args args, config, block_event, events
      config[:width] = config[:display_length] unless config.has_key? :width
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      useform = nil
      useform = @form if @current_object.empty?
      w = TextArea.new useform, config
      if block
        w.bind(block_event, &block)
      end
      return w
    end

    # similar definitions for textview and resultsettextview
    # NOTE This is not allowing me to send blocks,
    # so do not use for containers
    {
      'rbhex/core/widgets/rtextview' => 'TextView',
      'rbhex/experimental/resultsettextview' => 'ResultsetTextView',
      'rbhex/core/widgets/rcontainer' => 'Container',
      'rbhex/extras/rcontainer2' => 'Container2',
    }.each_pair {|k,p|
      eval(
           "def OLD#{p.downcase} *args, &block
              require \"#{k}\"
      config = {}
      # TODO confirm events many more
      events = [ :PRESS, :LEAVE, :ENTER ]
      block_event = events[0]
      _process_args args, config, block_event, events
      config[:width] = config[:display_length] unless config.has_key? :width
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      raise \"height needed for #{p.downcase}\" if !config.has_key? :height
      useform = nil
      useform = @form if @current_object.empty?
      w = #{p}.new useform, config
      if block
        w.bind(block_event, &block)
      end
      return w
           end"
           )
    }

    # table widget
    # @example
    #  data = [["Roger",16,"SWI"], ["Phillip",1, "DEU"]]
    #  colnames = ["Name", "Wins", "Place"]
    #  t = table :width => 40, :height => 10, :columns => colnames, :data => data, :estimate_widths => true
    #    other options are :column_widths => [12,4,12]
    #    :size_to_fit => true
    def edit_table *args, &block # earlier table
      require 'rbhex/extras/widgets/rtable'
      config = {}
      # TODO confirm events many more
      events = [ :ENTER_ROW,  :LEAVE, :ENTER ]
      block_event = events[0]
      _process_args args, config, block_event, events
      # if user is leaving out width, then we don't want it in config
      # else Widget will put a value of 10 as default, overriding what we've calculated
      if config.has_key? :display_length
        config[:width] = config[:display_length] unless config.has_key? :width
      end
      ext = config.delete :extended_keys

      model = nil
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      w = Table.new @form, config
      if ext
        require 'rbhex/extras/include/tableextended'
          # so we can increase and decrease column width using keys
        w.extend TableExtended
        w.bind_key(?w){ w.next_column }
        w.bind_key(?b){ w.previous_column }
        w.bind_key(?+) { w.increase_column }
        w.bind_key(?-) { w.decrease_column }
        w.bind_key([?d, ?d]) { w.table_model.delete_at w.current_index }
        w.bind_key(?u) { w.table_model.undo w.current_index}
      end
      if block
        w.bind(block_event, &block)
      end
      return w
    end

    # print a title on first row
    def title string, config={}
      ## TODO center it
      @window.printstring 1, 30, string, $normalcolor, 'reverse'
    end

    # print a sutitle on second row
    def subtitle string, config={}
      @window.printstring 2, 30, string, $datacolor, 'normal'
    end

    # creates a blank row
    def OLDblank rows=1, config={}
      @app_row += rows
    end

    # displays a horizontal line
    # takes col (column to start from) from current stack
    # take row from app_row
    #
    # requires width to be passed in config, else defaults to 20
    # @example
    #    hline :width => 55
    def hline config={}
      row = config[:row] || @app_row
      width = config[:width] || 20
      _position config
      col = config[:col] || 1
      @color_pair = config[:color_pair] || $datacolor
      @attrib = config[:attrib] || Ncurses::A_NORMAL
      @window.attron(Ncurses.COLOR_PAIR(@color_pair) | @attrib)
      @window.mvwhline( row, col, FFI::NCurses::ACS_HLINE, width)
      @window.attron(Ncurses.COLOR_PAIR(@color_pair) | @attrib)
      @app_row += 1
    end

    def TODOmultisplit *args, &block
      require 'rbhex/extras/widgets/rmultisplit'
      config = {}
      events = [ :PROPERTY_CHANGE,  :LEAVE, :ENTER ]
      block_event = events[0]
      _process_args args, config, block_event, events
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      config.delete :title
      useform = nil
      useform = @form if @current_object.empty?

      w = MultiSplit.new useform, config
      #if block
        #w.bind(block_event, w, &block)
      #end
      if block_given?
        @current_object << w
        #instance_eval &block if block_given?
        yield w
        @current_object.pop
      end
      return w
    end

    # create a readonly list
    # I don't want to rename this to list, as that could lead to
    # confusion, maybe rlist
    def OLDlistbox *args, &block # earlier basic_list
      require 'rbhex/core/widgets/rlist'
      config = {}
      #TODO check these
      events = [ :LEAVE, :ENTER, :ENTER_ROW, :LEAVE_ROW, :LIST_DATA_EVENT ]
      # TODO how to do this so he gets selected row easily
      block_event = :ENTER_ROW
      _process_args args, config, block_event, events
      # some guesses at a sensible height for listbox
      if !config.has_key? :height
        ll = 0
        ll = config[:list].length + 2 if config.has_key? :list
        config[:height] ||= ll
        config[:height] = 15 if config[:height] > 20
      end
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      config[:width] ||= longest_in_list(config[:list])+2
      #config.delete :title
      #config[:default_values] = config.delete :choose
      config[:selection_mode] = :single unless config.has_key? :selection_mode
      useform = nil
      useform = @form if @current_object.empty?

      w = List.new useform, config # NO BLOCK GIVEN
      if block_given?
        field.bind(block_event, &block)
      end
      return w
    end

    alias :basiclist :listbox # this alias will be removed

    def TODOmaster_detail *args, &block
      require 'rbhex/experimental/widgets/masterdetail'
      config = {}
      events = [:PROPERTY_CHANGE, :LEAVE, :ENTER ]
      block_event = nil
      _process_args args, config, block_event, events
      #config[:height] ||= 10
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      #config.delete :title
      useform = nil
      useform = @form if @current_object.empty?

      w = MasterDetail.new useform, config # NO BLOCK GIVEN
      if block_given?
        @current_object << w
        yield_or_eval &block
        @current_object.pop
      end
      return w
    end

    # scrollbar attached to the right of a parent object
    def OLDscrollbar *args, &block
      require 'rbhex/core/widgets/scrollbar'
      config = {}
      events = [:PROPERTY_CHANGE, :LEAVE, :ENTER  ] # # none really at present
      block_event = nil
      _process_args args, config, block_event, events
      raise "parent needed for scrollbar" if !config.has_key? :parent
      useform = nil
      useform = @form if @current_object.empty?
      sb = Scrollbar.new useform, config
    end

    # divider used to resize neighbouring components TOTEST XXX
    def OLDdivider *args, &block
      require 'rbhex/core/widgets/divider'
      config = {}
      events = [:PROPERTY_CHANGE, :LEAVE, :ENTER, :DRAG_EVENT  ] # # none really at present
      block_event = nil
      _process_args args, config, block_event, events
      useform = nil
      useform = @form if @current_object.empty?
      sb = Divider.new useform, config
    end

    # creates a simple readonly table, that allows users to click on rows
    # and also on the header. Header clicking is for column-sorting.
    def OLDcombo *args, &block
      require 'rbhex/core/widgets/rcombo'
      config = {}
      events = [:PROPERTY_CHANGE, :LEAVE, :ENTER, :CHANGE, :ENTER_ROW, :PRESS ] # XXX
      block_event = nil
      _process_args args, config, block_event, events
      _position(config)
      # if no width given, expand to flows width
      config[:width] ||= @stack.last.width if @stack.last
      #config.delete :title
      useform = nil
      useform = @form if @current_object.empty?

      w = ComboBox.new useform, config # NO BLOCK GIVEN
      if block_given?
        @current_object << w
        yield_or_eval &block
        @current_object.pop
      end
      return w
    end

    # ADD new widget above this

    # @endgroup

    # @group positioning of components

    # line up vertically whatever comes in, ignoring r and c
    # margin_top to add to margin of existing stack (if embedded) such as extra spacing
    # margin to add to margin of existing stack, or window (0)
    # NOTE: since these coordins are calculated at start
    # therefore if window resized i can't recalculate.
    #Stack = Struct.new(:margin_top, :margin, :width)
    def OLDstack config={}, &block
      @instack = true
      mt =  config[:margin_top] || 1
      mr =  config[:margin] || 0
      # must take into account margin
      defw = Ncurses.COLS - mr
      config[:width] = defw if config[:width] == :EXPAND
      w =   config[:width] || [50, defw].min
      s = Stack.new(mt, mr, w)
      @app_row += mt
      mr += @stack.last.margin if @stack.last
      @stack << s
      yield_or_eval &block if block_given?
      @stack.pop
      @instack = false if @stack.empty?
      @app_row = 0 if @stack.empty?
    end

    # keep adding to right of previous and when no more space
    # move down and continue fitting in.
    # Useful for button positioning. Currently, we can use a second flow
    # to get another row.
    # TODO: move down when row filled
    # TODO: align right, center
    def OLDflow config={}, &block
      @inflow = true
      mt =  config[:margin_top] || 0
      @app_row += mt
      col = @flowstack.last || @stack.last.margin || @app_col
      col += config[:margin] || 0
      @flowstack << col
      @flowcol = col
      yield_or_eval &block if block_given?
      @flowstack.pop
      @inflow = false if @flowstack.empty?
    end

    private

    def quit
      throw(:close)
    end
    private :quit

    def help
      display_app_help
    end
    private :help

    def init_ncurses
      VER::start_ncurses  # this is initializing colors via ColorMap.setup
      @stop_ncurses_on_close = true
    end
    private :init_ncurses

    # returns length of longest
    def longest_in_list list  #:nodoc:
      longest = list.inject(0) do |memo,word|
        memo >= word.length ? memo : word.length
      end
      longest
    end
    private :longest_in_list

    # returns longest item
    # rows = list.max_by(&:length)
    def longest_in_list2 list  #:nodoc:
      longest = list.inject(list[0]) do |memo,word|
        memo.length >= word.length ? memo : word
      end
      longest
    end
    private :longest_in_list2

    # if partial command entered then returns matches
    def _resolve_command opts, cmd
      return cmd if opts.include? cmd
      matches = opts.grep Regexp.new("^#{cmd}")
    end
    private :_resolve_command

    # Now i am not creating this unless user wants it. Pls avoid it.
    # Use either say_with_pause, or put $status_message in command of statusline
    # @deprecated please use {#status_line} instead of a message label
    def create_message_label row=Ncurses.LINES-1
      @message_label = RubyCurses::Label.new @form, {:text_variable => @message, :name=>"message_label",:row => row, :col => 0, :display_length => Ncurses.COLS,  :height => 1, :color => :white}
    end
    private :create_message_label

    def run &block
      begin
        @window = VER::Window.root_window
        awin = @window
        catch(:close) do
          @form = Form.new @window
          @form.bind_key([?\C-x, ?c], 'suspend') { suspend(false) do
            system("tput cup 26 0")
            system("tput ed")
            system("echo Enter C-d to return to application")
            system (ENV['PS1']='\s-\v\$ ')
            system(ENV['SHELL']);
          end
          }

          # this is a very rudimentary default command executer, it does not
          # allow tab completion. App should use M-x with names of commands
          # as in appgmail
          @form.bind_key(?:, 'prompt') {
            str = get_command_from_user
          }

          # this M-x stuff has to be moved out so it can be used by all. One should be able
          # to add_commands properly to this, and to C-x. I am thinking how to go about this,
          # and what function M-x actually serves.
          @form.bind_key(?\M-x, 'M-x commands'){
            opts = get_all_commands()
            @_command_history ||= Array.new
            # previous command should be in opts, otherwise it is not in this context
            cmd = rb_gets("Command: ", opts){ |q| q.default = @_previous_command; q.history = @_command_history }
            if cmd.nil? || cmd == ""
            else
              @_command_history << cmd unless @_command_history.include? cmd
              cmdline = cmd.split
              cmd = cmdline.shift
              # check if command is a substring of a larger command
              if !opts.include?(cmd)
                rcmd = _resolve_command(opts, cmd) if !opts.include?(cmd)
                if rcmd.size == 1
                  cmd = rcmd.first
                elsif !rcmd.empty?
                  rb_puts "Cannot resolve #{cmd}. Matches are: #{rcmd} "
                end
              end
              if respond_to?(cmd, true)
                @_previous_command = cmd
                begin
                  send cmd, *cmdline
                rescue => exc
                  $log.error "ERR EXC: send throwing an exception now. Duh. IMAP keeps crashing haha !! #{exc}  " if $log.debug?
                  if exc
                    $log.debug( exc)
                    $log.debug(exc.backtrace.join("\n"))
                    rb_puts exc.to_s
                  end
                end
              else
                rb_puts("Command [#{cmd}] not supported by #{self.class} ", :color_pair => $promptcolor)
              end
            end
          }

          @form.bind_key([?q,?q], 'quit' ){ throw :close } if $log.debug?

          $status_message ||= Variable.new # remember there are multiple levels of apps
          $status_message.value = ""

          if block
            begin
              yield_or_eval &block if block_given? # modified 2010-11-17 20:36
              # how the hell does a user trap exception if the loop is hidden from him ? FIXME
              loop
            rescue => ex
              $log.debug( "APP.rb rescue reached ")
              $log.debug( ex) if ex
              $log.debug(ex.backtrace.join("\n")) if ex
            ensure
              close
              # putting it here allows it to be printed on screen, otherwise it was not showing at all.
              if ex
                puts "========== EXCEPTION =========="
                p ex
                puts "==============================="
                puts(ex.backtrace.join("\n"))
              end
            end
            nil
          else
            self
          end
        end
      end
    end

    # TODO
    # process args, all widgets should call this
    def _process_args args, config, block_event, events  #:nodoc:
      args.each do |arg|
        case arg
        when Array
          # please don't use this, keep it simple and use hash NOTE
          # we can use r,c, w, h
          row, col, display_length, height = arg
          config[:row] = row
          config[:col] = col
          config[:display_length] = display_length if display_length
          config[:width] = display_length if display_length
          # width for most XXX ?
          config[:height] = height if height
        when Hash
          config.merge!(arg)
          if block_event
            block_event = config.delete(:block_event){ block_event }
            raise "Invalid event. Use #{events}" unless events.include? block_event
          end
        when String
          config[:name] = arg
          config[:title] = arg # some may not have title
          #config[:text] = arg # some may not have title
        end
      end
    end

    # position object based on whether in a flow or stack.
    # @app_row is prepared for next object based on this objects ht
    def OLD_position config  #:nodoc:
      unless @current_object.empty?
        $log.debug " WWWW returning from position #{@current_object.last} "
        return
      end
      if @inflow
        #col = @flowstack.last
        config[:row] = @app_row
        config[:col] = @flowcol
        $log.debug " YYYY config #{config} "
        if config[:text]
          @flowcol += config[:text].length + 5 # 5 came from buttons
        else
          @flowcol += (config[:length] || 10) + 5 # trying out for combo
        end
      elsif @instack
        # most likely you won't have row and col. should we check or just go ahead
        # what if he has put it 2011-10-19 as in a container
        col = @stack.last.margin
        config[:row] ||= @app_row
        config[:col] ||= col
        @app_row += config[:height] || 1 #unless config[:no_advance]
        # TODO need to allow stack to have its spacing, but we don't have an object as yet.
      end
    end
  end
end
