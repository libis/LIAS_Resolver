# coding: utf-8
require 'oci8'
require 'singleton'

class OracleConnectionPool
  include Singleton

  attr_reader :connection_pool

  def get_connection(db_user, db_pass, db_host)
    if @connection_pool.nil?
      @connection_pool = OCI8::ConnectionPool.new(0, 30, 1, db_user, db_pass, db_host)
      @connection_pool.nowait = false
      @connection_pool.timeout = 1
    else
      puts "Connection pool: #{@connection_pool.inspect} | connections: Min: #{@connection_pool.min} Max: #{@connection_pool.max} Open: #{@connection_pool.open_count} Busy:#{@connection_pool.busy_count}"
    end

    OCI8.new(db_user, db_pass, @connection_pool)
  end

end