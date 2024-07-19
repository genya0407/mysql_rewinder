# frozen_string_literal: true

require_relative "mysql_rewinder/version"
require_relative "mysql_rewinder/cleaner"
require 'set'
require 'tmpdir'
require 'fileutils'
require 'forwardable'
require 'logger'

class MysqlRewinder
  class << self
    extend Forwardable
    delegate %i[clean clean_all record_inserted_table] => :@instance

    def setup(db_configs, except_tables: [], adapter: :trilogy, logger: nil)
      @instance = new(db_configs: db_configs, except_tables: except_tables, adapter: adapter, logger: logger)
    end
  end

  def initialize(db_configs:, except_tables:, adapter:, logger:)
    @initialized_pid = Process.pid
    @inserted_table_record_dir = Pathname(Dir.tmpdir)
    @cleaners = db_configs.map do |db_config|
      Cleaner.new(
        db_config.transform_keys(&:to_sym),
        except_tables: except_tables,
        adapter: adapter,
        logger: logger
      )
    end
    @logger = logger
    reset_inserted_tables
  end

  def record_inserted_table(sql)
    return unless @initialized_pid

    @inserted_tables ||= Set.new
    new_inserted_tables = extract_inserted_tables(sql)

    return if new_inserted_tables.empty?

    @inserted_tables.merge(new_inserted_tables)
    File.write(
      @inserted_table_record_dir.join("#{@initialized_pid}.#{Process.pid}.inserted_tables").to_s,
      @inserted_tables.to_a.join(',')
    )
  end

  def reset_inserted_tables
    unless @initialized_pid == Process.pid
      raise "MysqlRewinder is initialize in process #{@initialized_pid}, but reset_inserted_tables is called in process #{Process.pid}"
    end

    @inserted_tables = Set.new
    files = Dir.glob(@inserted_table_record_dir.join("#{@initialized_pid}.*.inserted_tables").to_s)

    FileUtils.rm(files)
    @logger&.debug { "[MysqlRewinder] removed files: #{files.join(', ')}" } if files.any?
  end

  def calculate_inserted_tables
    unless @initialized_pid == Process.pid
      raise "MysqlRewinder is initialize in process #{@initialized_pid}, but calculate_inserted_tables is called in process #{Process.pid}"
    end

    Dir.glob(@inserted_table_record_dir.join("#{@initialized_pid}.*.inserted_tables").to_s).flat_map do |fname|
      File.read(fname).strip.split(',')
    end.uniq
  end

  def clean_all
    @cleaners.each(&:clean_all)
    reset_inserted_tables
  end

  def clean
    aggregated_inserted_tables = calculate_inserted_tables
    @cleaners.each { |c| c.clean(tables: aggregated_inserted_tables) }
    reset_inserted_tables
  end

  private

  def extract_inserted_tables(sql)
    insert_tables = Set.new
    sql.split(';').each do |statement|
      match = statement.match(/\A\s*INSERT(?:\s+IGNORE)?(?:\s+INTO)?\s+(?:\.*[`"]?([^.\s`"(]+)[`"]?)*/i)
      next unless match

      table = match[1]
      insert_tables << table if table
    end

    insert_tables
  end
end
