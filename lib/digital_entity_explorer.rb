require_relative 'soap_client'

class DigitalEntityExplorer < SoapClient

  def initialize
    super "DigitalEntityExplorer"
  end

  def search( tag, term, from, max, filter = nil)
    query = create_query tag, term, from, max, filter
    request :digital_entity_search, :general => general.to_s, :query => query.to_s
  end

  def create_query( tag, term, from, max, filter )
    from += 1 # bug in DTL web service
    query = create_document
    root = create_node('x_queries',
                       :namespaces => { :node_ns  => 'xb',
                                        'xb'      => 'http://com/exlibris/digitool/repository/api/xmlbeans'})
    query.root = root

    root << (x_query = create_node('x_query', :attributes => { 'type' => 'hql', 'name' => 'SET1' }))
    x_query << (x_select = create_node('x_select', :attributes => { 'from_answer' => from.to_s, 'to_answer' => (from + max - 1).to_s }))
    x_select << create_text_node('element', 'control')

    x_query << create_text_node('hql', %{select hc from HDeControl hc where #{create_where(tag, term)}#{create_filter(filter)} and (usagetype = 'ARCHIVE' or ((entitytype = 'COMPLEX' or entitytype = 'METS') and usagetype = 'VIEW'))})

#puts query.to_xml
    query
  end

  def create_where( tag, value )
    negate = false
    if tag =~ /!$/
      negate = true
      tag = tag[0..-2]
    end
    query_text = %{lower(#{tag}) }
    if value =~ /.*[^!][%_].*/
      query_text += %{not } if negate
      query_text += %{like }
    else
      query_text += ( negate ? %{<> } : %{= } )
    end
    query_text += %{lower('#{value.to_s}')}
    
  end

  def create_filter( filter )
    result = ['']
    if filter.is_a? Hash
      filter.each { |tag, value| result << create_where( tag, value) }
    end
    result.join ' and '
  end

end
