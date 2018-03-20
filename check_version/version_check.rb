#!/usr/bin/ruby
require 'yaml'
require 'nokogiri'
require 'find'
require 'fileutils'
require 'deep_merge'
require 'pathname'
require 'optparse'

class RubyYml
  def process_cmdargs
    opt_parser = OptionParser.new do |opts|
      opts.on('-f', '--file [file1.yml, file2.yml]', String, 'paths to yml component file') do |value|
        unless value
          puts 'please specific driver yml path'
          puts 'For example ruby version_check.rb -f kinetis/drv_gpio.yml'
          exit(0)
        end
        @file = value
      end
      opts.on('-s', '--soc [soc|...]', Array, 'choose file') do |value|
        unless value
          puts 'please specific soc name'
          puts 'For example ruby version_check.rb -s MK64F12'
          exit(0)
        end
        @soc = value
      end
    end
    opt_parser.parse!
    if @file.nil? && @soc.nil?
      path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/bin/generator/records/msdk/components/drivers/'
      dir(path)
      path_soc = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/bin/generator/records/msdk/components/socs/'
      dir_soc(path_soc)
      exit(1)
    elsif @file
      path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + "/bin/generator/records/msdk/components/drivers/#{@file}"
      version_check_common(path)
      exit(1) unless @all_match
    elsif @soc
      @soc.each do |value|
        path_soc = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + "/bin/generator/records/msdk/components/socs/#{value}/"
        dir_specific_soc(path_soc, value)
      end
      exit(1) unless @all_match
    else
      puts 'please use -f file.yml path or -s soc_name'
      exit(0)
    end
  end

  def dir_soc(path)
    path = path.tr('\\', '/')
    Dir.glob("#{path}**/*").each do |filepath|
      soc = File.basename(File.dirname(filepath))
      next if File.directory?(filepath)
      # next unless File.exist?(filepath)
      version_check_soc(filepath, soc)
    end
  end

  def dir_specific_soc(path, value)
    unless File.exist?(path)
      puts "ERROR: the path does not exit, please make sure soc name(#{value}) is correct."
    end
    path = path.tr('\\', '/')
    Dir.glob("#{path}**/*").each do |filepath|
      next if File.directory?(filepath)
      # puts "check #{value} soc specific driver version"
      version_check_soc(filepath, value)
    end
  end

  def version_check_soc(path, soc)
    content = File.read(path.tr('\\', '/'))
    content = YAML.safe_load(content.tr('\\', '/'))

    content.each do |_name, component|
      next unless component.class == Array
      component.each do |yml|
        driver_path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent + yml
        next unless File.exist?(driver_path)
        next unless driver_path.to_s.include?('drivers') || driver_path.to_s.include?('socs')
        get_versions(driver_path, soc)
      end
    end
  rescue Exception => e
    puts "#{path} check version fail"
    puts e
  end

  def show_log(_name, yml_version, head_version, match_change_log_version, change_log_version)
    if head_version.include?(yml_version.split('.').join(', ')) || head_version.include?(yml_version.split('.').join(',')) || \
       head_version.include?(yml_version.split('.').join('U, ')) || head_version.include?(yml_version.split('.').join('U,'))
      head_version = /\dU?,\s\dU?,\s\dU?/.match(head_version)
      if yml_version != match_change_log_version.to_s && change_log_version
        puts "#{_name}:"
        puts "  Change log version(#{match_change_log_version}) not match with YAML component version(#{yml_version}) and header file version(#{head_version})."
        puts '--------------------------------------------------------------------------------------'
      elsif yml_version != match_change_log_version.to_s && !change_log_version
        puts "#{_name}:"
        puts "  no ChangeLogKSDK.txt file"
        puts "  YAML component version(#{yml_version}) and header file version(#{head_version}) match."
        puts '--------------------------------------------------------------------------------------'
      else
        puts "#{_name}:"
        puts "  Change log version(#{match_change_log_version}), YAML component version(#{yml_version}) and header file version(#{head_version}) all match."
        puts '--------------------------------------------------------------------------------------'
        @all_match = 1
      end
    else
      head_version = /\dU?,\s\dU?,\s\dU?/.match(head_version)
      if yml_version != match_change_log_version && change_log_version
        puts "#{_name}:"
        puts "  Change log versoin(#{match_change_log_version}), YAML component version(#{yml_version}) and header file version(#{head_version}) not match"
      elsif yml_version != match_change_log_version && !change_log_version
        puts "The #{_name}:"
        puts "  no ChangeLogKSDK.txt file"
        puts "  YAML component version(#{yml_version}), header file version(#{head_version}) not match."
      end
      puts '--------------------------------------------------------------------------------------'
    end
  end

  def get_versions(driver_path, soc)
    driver_content = File.read(driver_path.to_s.tr('\\', '/'))
    driver_content = YAML.safe_load(driver_content.tr('\\', '/'))
    driver_content.each do |name, component|
      next unless component.key?('contents')
      if component['contents'].key?('component_info')
        @driver_version = component['contents']['component_info']['__common__']['version']
      end

      next unless component['contents'].key?('files')
      component['contents']['files'].each do |file|
        next unless file['source'].include?('h') && file['source'].include?('${')
        the_head = file['source'].gsub('${platform_devices_soc_name}', soc)
        head_path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/' + the_head
        # next unless head_path
        change_log_path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/' + File.dirname(the_head) + '/doxygen/ChangeLogKSDK.txt'
        driver_name = File.basename(the_head).split('.')[0].split('_')[1].upcase
        if File.exist?(change_log_path)
          contentc = ' '
          File.open(change_log_path, 'r') { |f| contentc = f.read }
          contentc.each_line do |line|
            @change_log_version = line if line.include?("Current #{driver_name}")
          end
        else
          @change_log_version = false
        end
        @match_change_log_version = /\dU?.\dU?.\dU?/.match(@change_log_version) if @change_log_version
        break unless File.exist?(head_path)
        content_head = ' '
        File.open(head_path, 'r') { |f| content_head = f.read }
        content_head.each_line do |line|
          @head_version_soc =  line if line.include?('MAKE_VERSION')
        end
        next unless @head_version_soc
        puts "check #{soc} soc specific driver version"
        show_log(name, @driver_version, @head_version_soc, @match_change_log_version, @change_log_version)
      end
    end
  end

  def dir(path)
    path = path.tr('\\', '/')
    Dir.glob("#{path}**/*").each do |filepath|
      next if File.directory?(filepath)
      version_check_common(filepath)
    end
  end

  def version_check_common(path)
    content = File.read(path.tr('\\', '/'))
    content = YAML.safe_load(content.tr('\\', '/'))
    @flag = false
    begin
      content.each do |_name, component|
        next unless component.key?('contents')
        if component['contents'].key?('files')
          size = component['contents']['files'].size
          for i in 0..size - 1
            head = component['contents']['files'][i]['source']
            next unless head.include?('.h') && !head.include?('${')
            head_path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/' + head
            change_log_path = Pathname.new(File.dirname(__FILE__)).realpath.parent.parent.to_s + '/' + File.dirname(head) + '/doxygen/ChangeLogKSDK.txt'
            driver_name = File.basename(head).split('.')[0].split('_')[1].upcase
            if File.exist?(change_log_path)
              contentc = ' '
              File.open(change_log_path, 'r') { |f| contentc = f.read }
              contentc.each_line do |line|
                @change_log_version = line if line.include?('Current')
              end
            else
              @change_log_version = false
            end
            @match_change_log_version = /\dU?.\dU?.\dU?/.match(@change_log_version) if @change_log_version
            next unless File.exist?(head_path)
            content1 = ' '
            File.open(head_path, 'r') { |f| content1 = f.read }
            content1.each_line do |line|
              @head_version = line if line.include?('MAKE_VERSION')
            end
          end
        end
        next unless @head_version
        next unless component['contents'].key?('component_info')
        yml_version = component['contents']['component_info']['__common__']['version']
        show_log(_name, yml_version, @head_version, @match_change_log_version, @change_log_version)
      end
    rescue Exception => e
      puts "content error #{path}"
      puts e
    end
  rescue Exception => e
    p e
    puts "error #{path}"
  end
end

if $PROGRAM_NAME == __FILE__

  obj_update_driver_yml = RubyYml.new
  obj_update_driver_yml.process_cmdargs

end
