# coding: utf-8

require 'sinatra'
require 'sinatra/base'
require 'sinatra/config_file'
require 'builder'
require 'cgi'
require 'set'
require './lib/digital_entity_explorer'

require './lias_resolver_helper'

class LiasResolver < Sinatra::Base
  include LiasResolverHelper

  register Sinatra::ConfigFile

  config_file 'lias_resolver.yml'

  THIS_URL = settings.this_url
  VIEWER   = settings.view_url
  VIEWER_X = settings.strm_url

  digital_entity_explorer = DigitalEntityExplorer.new
  connection = nil

  before do
    cache_control :public, :max_age => 36000
  end

  get '/lias/find_pid' do
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
#puts "Filter: #{filter}"

    result = digital_entity_explorer.search('label', term, from, max, filter)

    pid_list = result[:pids]
    totals = result[:result].xpath('//@total_num_results')
    total = 0
    total = totals[0].content.to_i if totals

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

          t_url = "#{THIS_URL}/get_pid?redirect&usagetype=THUMBNAIL&pid=#{p.to_s}&custom_att_3=stream"
          v_url = "#{THIS_URL}/get_pid?redirect&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"
          de = result[:result].xpath('//xb:digital_entity[pid=$pid]', nil, { :pid => p.to_s })[0]
          label = de.xpath('//control/label')[0].content
          etype = de.xpath('//control/entity_type')[0]
          etype = etype.content if etype
          c_url = "#{THIS_URL}/get_children?pid=#{p.to_s}"

          attributes = {
            'pid'   => "#{p.to_s}",
            'label' => "#{label}",
            'thumbnail' => "#{CGI::escapeHTML(t_url)}",
            'view'      => "#{CGI::escapeHTML(v_url)}"
          }

          attributes['children'] = "#{CGI::escapeHTML(c_url)}" if ['COMPLEX', 'METS'].include?(etype)
      
          xml.item(attributes)

        end # pid_list

      end # xml.result

    end # Builder

  end # get find_pid

  get '/lias/get_children' do
    pid = params['pid']

    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    max = params['max_results']
    from = params['from']

    max = max.to_i | 20
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

      attributes['next'] = "#{_next.to_s}" if _more > 0
      attributes['more'] = "#{_more.to_s}" if _more > 0

      xml.result(attributes) do

        pid_list.each do |h|

          p = h['PID']
          label = h['LABEL']

          t_url = "#{THIS_URL}/get_pid?redirect&usagetype=THUMBNAIL&pid=#{p.to_s}&custom_att_3=stream"
          v_url = "#{THIS_URL}/get_pid?redirect&usagetype=VIEW_MAIN,VIEW&pid=#{p.to_s}"

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
    

  end

  get '/lias/get_pid' do

    pid = params['pid']
    
    halt 400, 'Missing \'pid\' parameter' if pid.nil? or pid.empty?

    viewer = params['redirect']
    if viewer.nil? and params.has_key?('redirect')
      if params.has_key?('custom_att_3') and params['custom_att_3'] == 'stream'
        viewer = VIEWER
      else
        viewer = VIEWER_X
      end
    end

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
    end

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
      end
      viewer += "custom_att_2=simple_viewer"
      redirect viewer

    else
      headers 'Content-type' => 'text/xml', 'Charset' => 'utf-8'
      builder do |xml|
        xml.instruct! :xml, version: '1.0', encoding: 'utf-8'
        xml.result('source_pid' => pid,'target_usagetype'  => usagetype.join(',')) do
          pid_list.each do |p|
            xml.target_pid p.to_s
          end
        end
      end

    end

  end

  run! if app_file == $0

end

