# coding: utf-8
require 'savon'

require_relative 'xml_document'

class SoapClient

  attr_reader :client

  #noinspection RubyResolve
  def initialize(service)
    @client = Savon.client(
        soap_version: 2,
        wsdl: "http://aleph08.libis.kuleuven.be:1801/de_repository_web/services/#{service}?wsdl",
        raise_errors: false,
        log_level: :info,
        log: false,
        read_timeout: 120,
        open_timeout: 120,
    )
  end

  def request(method, body)
    response = @client.call(method, message: body)
    parse_result response
  end

  def parse_result(response)
    error = []
    pids = []
    mids = []
    de = []
    r = response.to_hash
    result = get_xml_response(r)
    doc = Nokogiri::XML(result)
    if response.success?
      doc.xpath('//error_description').each { |x| error << x.content unless x.content.nil? }
      doc.xpath('//pid').each { |x| pids << x.content unless x.content.nil? }
      doc.xpath('//mid').each { |x| mids << x.content unless x.content.nil? }
      doc.xpath('//xb:digital_entity').each { |x| de << x.to_s }
    else
      error << "SOAP Fault: " + response.soap_fault.to_s if response.soap_fault?
      error << "HTTP Error: " + response.http_error.to_s if response.http_error?
    end
    {:error => error, :pids => pids, :mids => mids, :digital_entities => de, :result => doc.document}
  end

  def general(owner = 'LIA01', user = 'super:lia01', password = 'super')
    doc = XmlDocument.new
    root = doc.create_node('general')
    doc.add_namespaces(root, {
        :node_ns => 'xb',
        'xb' => 'http://com/exlibris/digitool/repository/api/xmlbeans'})
    doc.root = root
    root << doc.create_text_node('application', 'DIGITOOL-3')
    root << doc.create_text_node('owner', owner)
    root << doc.create_text_node('interface_version', '1.0')
    root << doc.create_text_node('user', user)
    root << doc.create_text_node('password', password)
    doc.document
  end

  def get_xml_response(response)
    response.first[1][response.first[1][:result].to_s.gsub(/\B[A-Z]+/, '_\&').downcase.to_sym]
  end

end
