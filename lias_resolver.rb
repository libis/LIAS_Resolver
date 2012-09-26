# coding: utf-8

require 'cgi'
require 'set'

require 'sinatra'
require 'sinatra/base'
require 'sinatra/config_file'
require 'builder'
require 'haml'

require_relative 'lib/digital_entity_explorer'
require_relative 'lib/digital_entity_manager'
require_relative 'lib/meta_data_manager'
require_relative 'lib/xml_document'

require_relative 'lias_resolver_helper'

#noinspection RubyStringKeysInHashInspection,RubyResolve
class LiasResolver < Sinatra::Base

  register Sinatra::ConfigFile

  config_file 'lias_resolver.yml'

  set :static, true

  before do
    cache_control :public, :max_age => 36000
  end

  get '/find_pid' do
    key = params['key']
    term = params['search']
    max = params['max_results']
    from = params['from']
    filter_text = params['filter']
    sort_text = params['sort']
    operator = params['operator']

    key ||= 'label'
    max = max.to_i | 20
    from = from.to_i

    options = {}

    filter_text.split('|').each do |f|
      a = f.split(':')
      options[:filter] ||= {}
      options[:filter][a[0]] = a[1]
    end if filter_text

    sort_text.split('|').each do |s|
      if s.downcase == 'random'
        options[:sort] = %w(dbms_random.value)
        break
      end
      options[:sort] ||= []
      options[:sort] << s
    end if sort_text

    if operator
      options[:operator] = operator
    end

    result = DigitalEntityExplorer.instance.search(key, term, from, max, options)

    pid_list = result[:pids]

    totals = result[:result].xpath('//@total_num_results')
    total = 0
    total = totals.first.content.to_i if totals

    _next = from + pid_list.length
    _last = _next - 1
    _more = total - _next

    headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'

    builder do |xml|

      xml.instruct! :xml, version: '1.0', encoding: 'utf-8'

      attributes = {
        'total'  => "#{total.to_s}",
        'first'  => "#{from.to_s}",
        'last'   => "#{_last.to_s}"
      }

      attributes['search'] = "#{CGI::escapeHTML(term)}" if term

      attributes['next'] = "#{_next.to_s}" if _more > 0
      attributes['more'] = "#{_more.to_s}" if _more > 0

      xml.result(attributes) do

        pid_list.each do |p|

          t_url = "#{settings.this_url}/get_pid?stream&usagetype=THUMBNAIL&pid=#{p.to_s}"
          v_url = "#{settings.this_url}/get_pid?view&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"
          de = result[:result].xpath('//xb:digital_entity[pid=$pid]', nil, { :pid => p.to_s }).first
          label = de.xpath('control/label').first.content
          etype = de.xpath('control/entity_type').first
          etype = etype.content if etype
          c_url = "#{settings.this_url}/get_children?pid=#{p.to_s}"

          attributes = {
            'pid'   => "#{p.to_s}",
            'label' => "#{label}",
            'thumbnail' => "#{CGI::escapeHTML(t_url)}",
            'view'      => "#{CGI::escapeHTML(v_url)}"
          }

          attributes['children'] = "#{CGI::escapeHTML(c_url)}" if %w(COMPLEX METS).include?(etype)

          xml.item(attributes) do

            de.xpath("mds/md[name = 'descriptive']").each { |md|

              mid = md.xpath('mid').first.content

              attributes = {
                'mid' => mid,
                'type' => md.xpath('type').first.content,
                'url' => settings.this_url + '/get_metadata?mid=' + mid
              }

              xml.metadata(attributes)
            }

          end #xml.item

        end # pid_list

      end # xml.result

    end # Builder

  end # get find_pid

  get '/get_children' do
    pid = params['pid']

    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    max = params['max_results']
    from = params['from']

    max ||= 20
    max = max.to_i

    from ||= 0
    from = from.to_i

    result = collect_child_pids pid, from, max

    total = result[:count]
    pid_list = result[:pids]

    _next = from + pid_list.length
    _last = _next - 1
    _more = total - _next

    headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'

    builder do |xml|

      xml.instruct! :xml, version: '1.0', encoding: 'utf-8'

      attributes = {
        'parent' => "#{pid}",
        'total'  => "#{total.to_s}",
        'first'  => "#{from.to_s}",
        'last'   => "#{_last.to_s}"
      }

      if _more > 0
        attributes['next'] = "#{_next.to_s}"
        attributes['more'] = "#{_more.to_s}"
        attributes['next_url'] = "#{settings.this_url}/get_children?pid=#{pid}&from=#{_next.to_s}&max_results=#{max}"
      end # if _more > 0

      xml.result(attributes) do

        pid_list.each do |h|

          p = h['PID']
          label = h['LABEL']

          t_url = "#{settings.this_url}/get_pid?stream&usagetype=THUMBNAIL&pid=#{p.to_s}"
          v_url = "#{settings.this_url}/get_pid?view&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"

          attributes = {
            'pid'   => "#{p.to_s}",
            'label' => "#{label}",
            'thumbnail' => "#{CGI::escapeHTML(t_url)}",
            'view'      => "#{CGI::escapeHTML(v_url)}"
          }

          xml.item(attributes)

        end # pid_list

      end # xml.result

    end # Builder
    
  end # get_children

  get '/get_pid' do

    pid = params['pid']
    
    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    usagetype = params['usagetype']
    usagetype = '' unless usagetype

    ut = []
    lookup_type = nil

    if usagetype.empty?
      lookup_type = :exact
    elsif usagetype =~ /^ANY$/i
      lookup_type = :any
    elsif usagetype =~/^NULL$/i
      lookup_type = :null
      ut = [nil, '']
    elsif usagetype.kind_of? String
      lookup_type = :array
      ut = usagetype.split ','
    else
      halt 400, 'Bad usagetype parameter value'
    end # if usage_type

    pid_list = get_manifestations pid, ut, lookup_type

    action = nil

    if params.has_key?('redirect') and params['redirect'].nil?
      if params.has_key?('custom_att_3') and params['custom_att_3'] == 'stream'
        action = :stream
      else
        action = :view
      end # if params.has_key?
    end # if viewer.nil?

    action = :stream if params.has_key?('stream')
    action = :view if params.has_key?('view')

    if action.nil?
      headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
      builder do |xml|
        xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
        xml.result('source_pid' => pid, 'target_usagetype' => usagetype) do
          pid_list.each do |usage_type, pids|
            next unless pids
            pids.each do |target_pid|
              xml.target_pid({'usagetype' => usage_type}, target_pid.to_s)
            end
          end # pid_list.each
        end # xml.result
      end # builder

    else
      extra_params = params
      extra_params.delete 'usagetype'
      extra_params.delete 'redirect'
      extra_params.delete 'stream'
      extra_params.delete 'view'
      extra_params.delete 'custom_att_3'

      halt 400, 'Object not found. PID or manifestation does not exist.' unless pid_list.size > 0

      target_pid = pid_list.values.flatten.first
      extra_params['pid'] = target_pid

      viewer = params['redirect']
      viewer = (has_accessrights?(target_pid) ? settings.direct_url : settings.proxy_url) if viewer.nil?

      viewer += "?"
      extra_params.each do |k, v|
        viewer += "#{k.to_s}=#{v.to_s}&"
      end # each extra_params
      viewer += "custom_att_2=simple_viewer"
      viewer += "&custom_att_3=stream" if action == :stream
      redirect viewer

    end # unless

  end # get_pid

  get '/get_object' do

    pid = params['pid']

    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

  end

  get '/get_mid' do

    pid = params['pid']

    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    mid_list = get_metadata_ids

    headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
    builder { |xml|
      xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
      xml.result(pid: pid) {
        mid_list.each { |mid, md_type|
          xml.metadata(mid: mid, type: md_type)
        } # each md
      } # xml.result
    } # builder

  end # get_mid

  get '/get_metadata' do

    pid = params['pid']
    mid = params['mid']

    result = nil
    attributes = {}

    if mid and !mid.nil?
      result = MetaDataManager.instance.retrieve mid
      attributes[:mid] = mid
    elsif pid and !pid.nil?
      result = DigitalEntityManager.instance.retrieve_object pid
      attributes[:pid] = pid
    else
      halt 400, 'Missing \'pid\' or \'mid\' parameter'
    end

    headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
    builder { |xml|
      xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
      xml.result(attributes) {
        result[:result].xpath('//mds/md[name=\'descriptive\']').each { |md|
          xml.metadata(mid: md.xpath('mid').first.content, type: md.xpath('type').first.content) {
            doc = XmlDocument.parse(md.xpath('value').first.content)
            xml << doc.root.to_xml + "\n" if doc and doc.root
          } # xml.metadata
        } # each md
      } # xml.result
    } # builder
  end # get_metadata

  get '/help' do
    haml :help
  end

  get '/find_pid.help' do
    haml :find_pid
  end

  get '/get_children.help' do
    haml :get_children
  end

  get '/get_pid.help' do
    haml :get_pid
  end

  get '/get_mid.help' do
    haml :get_mid
  end

  get '/get_metadata.help' do
    haml :get_metadata
  end

  run! if app_file == $0

end

