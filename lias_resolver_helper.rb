# coding: utf-8

require_relative 'lib/digital_entity_manager'

class LiasResolver < Sinatra::Base

  helpers do

    register Sinatra::ConfigFile

    config_file 'lias_resolver.yml'

    def get_digital_entity(pid, extended = false)

      reply = DigitalEntityManager.instance.retrieve_object(pid, extended)

      return nil unless reply and reply[:digital_entities]

      reply[:result].xpath('//xb:digital_entity[pid=$pid]', nil, { :pid => pid.to_s }).first

    end

    def has_accessrights?(pid)

      digital_entity = get_digital_entity pid, true
      return nil unless digital_entity

      return true unless digital_entity.xpath('mds/md[type=\'rights_md\' and name=\'accessrights\']').empty?

      false

    end

    def get_usagetype(pid, digital_entity = nil)

      digital_entity = get_digital_entity pid unless digital_entity
      return nil unless digital_entity

      usage_type = digital_entity.xpath('control/usage_type')
      usage_type = digital_entity.xpath('usage_type') unless usage_type and !usage_type.empty?
      usage_type = usage_type.first.text if usage_type

      if usage_type == 'VIEW'
        file_name = digital_entity.xpath('stream_ref/file_name').first.text
        if file_name =~ /VIEW_MAIN/
          usage_type = 'VIEW_MAIN'
        end
      end

      return usage_type
    end

    def get_metadata_ids(pid)

      digital_entity = get_digital_entity pid

      result = []

      if digital_entity
        digital_entity.xpath('mds/md[name=\'descriptive\']').each { |md|
          result << [md.xpath('mid').first.content, md.xpath('type').first.content]
        } # each md
      end

      result
    end

    def get_all_manifestations(pid)

      result = {}

      digital_entity = get_digital_entity pid, true
      return result unless digital_entity

      usage_type = get_usagetype pid, digital_entity

      result[usage_type] ||= []
      result[usage_type] << pid

      digital_entity.xpath('relations/relation[type=\'manifestation\']').each do |manifestation|

        pid = manifestation.xpath('pid').first.text

        ut = get_usagetype pid

        result[ut] ||= []
        result[ut] << pid

      end

      result

    end

    def get_manifestations(pid, usage_type, lookup_type)

      if lookup_type == :exact
        ut = get_usagetype pid
        return { ut => [pid] }
      end

      manifestations = get_all_manifestations(pid)

      case lookup_type
        when :any
          return manifestations
        when :array
        when :null
        else
          return nil
      end

      usage_type.inject({}) { |h, ut| h[ut] = manifestations[ut]; h }

    end

    def collect_child_pids( pid, from, max )

      pid_list = []
      total = 0

      digital_entity = get_digital_entity pid, true

      if digital_entity

        children = digital_entity.xpath('relations/relation[type=\'include\' and usage_type=\'ARCHIVE\']')

        children.each do |child|
          pid = child.xpath('pid').first.text
          label = child.xpath('label').first.text
          pid_list << {'PID' => pid, 'LABEL' => label}
        end

        pid_list.sort_by! { |x| x['LABEL'] }

        total = children.size

      end

      pid_list = pid_list[from...from+max]

      { count: total, pids: pid_list }

    end

  end

end

