# coding: utf-8

require 'sinatra'
require 'sinatra/base'
require 'sinatra/config_file'
require 'builder'
require 'cgi'
require 'set'
require './lib/digital_entity_explorer'
require './lib/digital_entity_manager'
require './lib/meta_data_manager'
require './lib/xml_document'

require './lias_resolver_helper'

class LiasResolver < Sinatra::Base

  register Sinatra::ConfigFile

  config_file 'lias_resolver.yml'

  digital_entity_explorer = DigitalEntityExplorer.new
  connection = nil

  def initialize
    set :root, File.dirname(__FILE__)
    set :static, true
  end

  before do
    cache_control :public, :max_age => 36000
  end

  get '/find_pid' do
    term = params['search']
    max = params['max_results']
    from = params['from']
    filter_text = params['filter']

    max = max.to_i | 20
    from = from.to_i

    halt 400, 'Missing \'term\' parameter' if term.nil? or term.empty?

    filter = {}
    filter_text.split('|').each do |f|
      a = f.split(':')
      filter[a[0]] = a[1]
    end if filter_text

    result = digital_entity_explorer.search('label', term, from, max, filter)
puts result[:result]

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
        'search' => "#{CGI::escapeHTML(term)}",
        'total'  => "#{total.to_s}",
        'first'  => "#{from.to_s}",
        'last'   => "#{_last.to_s}"
      }

      attributes['next'] = "#{_next.to_s}" if _more > 0
      attributes['more'] = "#{_more.to_s}" if _more > 0

      xml.result(attributes) do

        pid_list.each do |p|

          t_url = "#{settings.this_url}/get_pid?redirect&usagetype=THUMBNAIL&pid=#{p.to_s}&custom_att_3=stream"
          v_url = "#{settings.this_url}/get_pid?redirect&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"
          de = result[:result].xpath('//xb:digital_entity[pid=$pid]', nil, { :pid => p.to_s }).first
          label = de.xpath('//control/label').first.content
          etype = de.xpath('//control/entity_type').first
          etype = etype.content if etype
          c_url = "#{settings.this_url}/get_children?pid=#{p.to_s}"

          attributes = {
            'pid'   => "#{p.to_s}",
            'label' => "#{label}",
            'thumbnail' => "#{CGI::escapeHTML(t_url)}",
            'view'      => "#{CGI::escapeHTML(v_url)}"
          }

          attributes['children'] = "#{CGI::escapeHTML(c_url)}" if ['COMPLEX', 'METS'].include?(etype)

          xml.item(attributes) do

            de.xpath('//mds/md[name = \'descriptive\']').each { |md|
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

    max = max.to_i | 20
    from = from.to_i | 0

    result = collect_child_pids pid, from, max, connection

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

          t_url = "#{settings.this_url}/get_pid?redirect&usagetype=THUMBNAIL&pid=#{p.to_s}&custom_att_3=stream"
          v_url = "#{settings.this_url}/get_pid?redirect&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"

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

    viewer = params['redirect']
    if viewer.nil? and params.has_key?('redirect')
      if params.has_key?('custom_att_3') and params['custom_att_3'] == 'stream'
        viewer = settings.view_url
      else
        viewer = settings.strm_url
      end # if params.has_key?
    end # if viewer.nil?

    usagetype = params['usagetype']
    if usagetype.empty?
      lookup_type = :excact
    elsif usagetype =~ /^ANY$/i
      lookup_type = :any
    elsif usagetype =~/^NULL$/i
      lookup_type = :null
    elsif usagetype.kind_of? String
      usagetype = usagetype.split ','
      lookup_type = :array
    else
      lookup_type = :error
    end # if usage_type

    sql = make_sql lookup_type
    pid_list = run_query sql, pid, usagetype, connection

    unless viewer.nil?
      extra_params = params
      extra_params.delete 'usagetype'
      extra_params.delete 'redirect'

      halt 400, 'Object not found. PID or manifestation does not exist.' unless pid_list.size > 0 

      extra_params['pid'] = pid_list.first

      viewer += "?"
      extra_params.each do |k,v|
        viewer += "#{k.to_s}=#{v.to_s}&"
      end # each extra_params
      viewer += "custom_att_2=simple_viewer"
      redirect viewer

    else
      headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
      builder do |xml|
        xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
        xml.result('source_pid' => pid,'target_usagetype'  => usagetype.join(',')) do
          pid_list.each do |p|
            xml.target_pid p.to_s
          end # pid_list.each
        end # xml.result
      end # builder

    end # unless

  end # get_pid

  get '/get_mid' do

    pid = params['pid']

    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    result = DigitalEntityManager.instance.retrieve_object pid

    headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
    builder { |xml|
      xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
      xml.result(pid: pid) {
        result[:result].xpath('//mds/md[name=\'descriptive\']').each { |md|
          xml.metadata(mid: md.xpath('mid').first.content, type: md.xpath('type').first.content)
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
            xml << doc.root.to_xml + "\n"
          } # xml.metadata
        } # each md
      } # xml.result
    } # builder
  end # get_metadata


  run! if app_file == $0

end

