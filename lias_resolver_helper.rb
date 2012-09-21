# coding: utf-8
require 'lib/oracle_connection_pool'

class LiasResolver < Sinatra::Base

  helpers do

    register Sinatra::ConfigFile

    config_file 'lias_resolver.yml'


    def oracle_connect(connection)
      if connection.nil?
        connection = OracleConnectionPool.instance.get_connection settings.db_user, settings.db_pass, settings.db_host
        puts "Requested new connection: #{connection.inspect}"
      end
      connection
    end

    def make_sql(lookup_type)
      sql = ''

      case lookup_type
      when :null
        sql = <<-SQL
SELECT pid
  FROM hdecontrol
   WHERE usagetype is NULL
     AND pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.control
  JOIN hdecontrol c2 ON c2.id = r.targetcontrol
  WHERE r.type = 3
    AND c1.usagetype is NULL
    AND c2.pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.targetcontrol
  JOIN hdecontrol c2 ON c2.id = r.control
  WHERE r.type = 3
    AND c1.usagetype is NULL
    AND c2.pid = :pid
SQL
      when :any
        sql = <<-SQL
SELECT pid
  FROM hdecontrol
  WHERE pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.control
  JOIN hdecontrol c2 ON c2.id = r.targetcontrol
  WHERE r.type = 3
    AND c2.pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.targetcontrol
  JOIN hdecontrol c2 ON c2.id = r.control
  WHERE r.type = 3
    AND c2.pid = :pid
SQL
      when :array
        sql = <<-SQL
SELECT pid
  FROM hdecontrol
  WHERE usagetype = :usagetype
    AND pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.control
  JOIN hdecontrol c2 ON c2.id = r.targetcontrol
  WHERE r.type = 3
    AND c1.usagetype = :usagetype
    AND c2.pid = :pid
UNION
SELECT c1.pid
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.targetcontrol
  JOIN hdecontrol c2 ON c2.id = r.control
  WHERE r.type = 3
    AND c1.usagetype = :usagetype
    AND c2.pid = :pid
SQL
      when :exact
      when :error
        return nil
        else
          # type code here
      end

      sql

    end

    def collect_pids_from_cursor( cursor )
      pid_list = []
      cursor.exec
      while (pid = cursor.fetch)
        pid_list << pid.join
      end
      pid_list
    end

    def run_query(sql, pid, usagetype, connection)

      return [] unless sql
      return [pid.to_s] if sql.empty?

      result = [].to_set

      begin
        connection = oracle_connect(connection)
        cursor = connection.parse sql
        cursor.bind_param(':pid', pid.to_s)

        return collect_pids_from_cursor(cursor) unless usagetype.kind_of? Array

        max_string = usagetype.max_by { |x| x.length }
        cursor.bind_param(':usagetype', max_string)
        usagetype.each do |ut|
          cursor[':usagetype'] = ut
          result += collect_pids_from_cursor cursor
        end

      ensure
        cursor.close if cursor
      end

      result

    end

    def collect_child_pids( pid, from, max, connection )

     base_sql = <<-SQL
SELECT c1.pid pid, c1.label label
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.control
  JOIN hdecontrol c2 ON c2.id = r.targetcontrol
 WHERE r.type = 2
   AND c1.usagetype = 'VIEW'
   AND c2.pid = :pid
    UNION
SELECT c1.pid pid, c1.label label
  FROM hderelation r
  JOIN hdecontrol c1 ON c1.id = r.targetcontrol
  JOIN hdecontrol c2 ON c2.id = r.control
 WHERE r.type = 2
   AND c1.usagetype = 'VIEW'
   AND c2.pid = :pid
    MINUS
SELECT c.pid pid, c.label label
  FROM hdepidmid r
  JOIN hdecontrol c ON c.id = r.hdecontrol
  JOIN hdemetadata m ON m.id = r.hdemetadata
 WHERE m.mdid = 15
SQL

      sql = <<-SQL
SELECT pid, label
  FROM (
    SELECT pid, label, ROWNUM rn
      FROM (
             #{base_sql}
           )
     WHERE ROWNUM <= :max_row
       )
 WHERE rn >= :min_row
SQL

      count_sql = <<-SQL
SELECT count(*)
  FROM (
         #{base_sql}
       )
SQL

      pid_list = []
      total = 0

      begin

        connection = oracle_connect(connection)
        cursor = connection.parse count_sql
        cursor.bind_param(':pid', pid.to_s)
        cursor.exec
        total = cursor.fetch[0].to_i
        cursor.close

        connection = oracle_connect(connection)
        cursor = connection.parse sql
        cursor.bind_param(':pid', pid.to_s)
        min_row = from + 1
        max_row = from + max
        cursor.bind_param(':min_row', min_row.to_s)
        cursor.bind_param(':max_row', max_row.to_s)
        cursor.prefetch_rows = max
        cursor.exec
        while (h = cursor.fetch_hash)
          pid_list << h
        end

      ensure
        cursor.close
#        connection.logoff

      end

      { count: total, pids: pid_list }

    end

  end

end

