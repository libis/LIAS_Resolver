# coding: utf-8
require 'singleton'

require_relative 'soap_client'

class DigitalEntityExplorer < SoapClient
  include Singleton

  def initialize
    super "DigitalEntityExplorer"
  end

  def search(tag, term, from, max, options = {})
    query = create_query tag, term, from, max, options
    request :digital_entity_search, :general => general.to_s, :query => query.to_s
  end

  def create_query(tag, term, from, max, options)
    from += 1 # bug in DTL web service
    query = XmlDocument.new
    root = query.create_node('x_queries',
                             :namespaces => {:node_ns => 'xb',
                                             'xb' => 'http://com/exlibris/digitool/repository/api/xmlbeans'})
    query.root = root

    root << (x_query = query.create_node('x_query', :attributes => {'type' => 'hql', 'name' => 'SET1'}))
    x_query << (x_select = query.create_node('x_select', :attributes => {'from_answer' => from.to_s, 'to_answer' => (from + max - 1).to_s}))
    x_select << query.create_text_node('element', 'all')

    query_text = [] << 'select' << 'hc' << 'from' << 'HDeControl' << 'hc'
    where_parts = ["(usagetype='ARCHIVE' or ((entitytype='COMPLEX' or entitytype='METS') and usagetype='VIEW'))"]
    where_parts << "status is null"
    where_parts << create_filter(options[:filter]) if options[:filter]
    where_parts << create_where(tag, term, options[:operator]) unless tag.nil? or tag.empty? or term.nil? or term.empty?
    query_text << 'where' << where_parts.join(' and ')
    query_text << create_sort(options[:sort])
    x_query << query.create_text_node('hql', query_text.join(' '))

puts query.to_xml
    query.document
  end

  def create_where(tag, value, operator_input = nil)
    operator = operator_input || '='
    case_sensitive = true
    if (matchdata = /^(.*)(~)$/.match(tag))
      tag = matchdata[1]
      case matchdata[2]
        when '~'
          case_sensitive = false
        else
      end
    end

    wildcard = operator_input.nil? && (value =~ /.*[^!][%_].*/)

    query_text = [] << (case_sensitive ? tag : "upper(#{tag})")

    if wildcard
      operator = 'like'
      value = "'#{value}'" if not value =~ /^'.*'$/
    end

    query_text << operator
    query_text << (case_sensitive ? value : "upper(#{value})")
    query_text.join ' '
  end

  def create_filter(filter)
    result = []
    if filter.is_a? Hash
      filter.each { |tag, value| result << create_where(tag, value) }
    end
    result.join ' and '
  end

  def create_sort(sort = [])
    return '' if sort.nil? or sort.empty?
    'order by ' << sort.join(', ')
  end

end
