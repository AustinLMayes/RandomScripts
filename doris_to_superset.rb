require 'common'
require 'yaml'
require 'active_support/core_ext/hash'

SQL_SESH = MysqlSession.new("127.0.0.1", "root", nil)

DATABASE = ARGV[0]

def determine_col_desc(col_name)
  return "The tenant that this data belongs to" if col_name == "tenant_id"
  return "Aggregation grouping size (e.g., hour, day, week)" if col_name == "bucket_size"
  return "The platform (e.g., Bedrock, Java) of the user" if col_name == "platform"
  return "Country that the user is connecting from" if col_name == "country"
  return "The ASN name of the user's network" if col_name == "asn_name"
  return "The device type (e.g., PC, iPhone) of the user" if col_name == "device"
  return "The region that the user is connecting to" if col_name == "region"
  return "The role of the instance the user is connecting to" if col_name == "role_id"
  return "The version of the user's client" if col_name == "version"
  return "Bundle name being sold" if col_name == "bundle_name"
  return "Source of the interaction (e.g., preview, button)" if col_name == "click_source"
  return "Name of the loot item previewed or interacted with" if col_name == "shown_loot"
  return "The role of the map being selected" if col_name == "selected_role"
  return "Name of the map being selected" if col_name == "selected_division"
  return "Name of the rank being purchased or renewed" if col_name == "rank_name" || col_name == "rank_id"
  return "The reason the store prompt was shown to the user" if col_name == "prompt_reason"
  return "Input mode of the user (e.g., touch, controller, keyboard)" if col_name == "input_mode"
  error "Unknown column #{col_name}"
end

def determine_table_desc(table_name)
  return gen_table_desc("abandoned_connections", table_name, "Number of users who logged in but didn't join any games") if table_name.include?("abandoned_connections")
  return gen_table_desc("active_users", table_name, "Number of unique users active during the time period") if table_name.include?("active_users")
  return gen_table_desc("game_length", table_name, "Length of a single game session in seconds") if table_name.include?("game_length")
  return gen_table_desc("logins", table_name, "Number of user logins") if table_name.include?("logins")
  return gen_table_desc("loot_interactions", table_name, "Users interacting with loot previews/buttons") if table_name.include?("loot_interactions")
  return gen_table_desc("map_selections", table_name, "Users selecting maps for gameplay") if table_name.include?("map_selections")
  return gen_table_desc("new_vs_returning", table_name, "Number of unique new and returning users") if table_name.include?("new_vs_returning")
  return gen_table_desc("purchase_renewals", table_name, "Users who extended an active subscription") if table_name.include?("purchase_renewals")
  return gen_table_desc("purchase_resubscriptions", table_name, "Users who purchased a subscription with an active permanent rank") if table_name.include?("purchase_resubscriptions")
  return gen_table_desc("purchases_no_source", table_name, "Users who made purchases without a store prompt") if table_name.include?("purchases_no_source")
  return gen_table_desc("session_length", table_name, "Length of a user session in seconds") if table_name.include?("session_length")
  return gen_table_desc("store_prompts", table_name, "Prompts for users to make purchases when they lack a permission") if table_name.include?("store_prompts")
  return gen_table_desc("subscription_churn_by_cycle", table_name, "Users who did not renew their subscription after it expired, grouped by subscription cycle") if table_name.include?("subscription_churn_by_cycle")
  return gen_table_desc("subscription_cohort_retention", table_name, "Cohort analysis of subscription retention over time") if table_name.include?("subscription_cohort_retention")
  return gen_table_desc("time_online", table_name, "Total time users spent online in seconds") if table_name.include?("time_online")
  error "Unknown table #{table_name}"
end

GROUPS = [
  ["st_platform", "Platform"],
  ["net_country", "Country"],
  ["st_device", "Device"],
  ["st_region", "Region"],
  ["role", "Role"],
  ["net_asn_name", "ASN Name"],
  ["st_version", "Version"],
  ["st_input_mode", "Input Mode"]
]

def gen_table_desc(base_name, full_name, base_desc)
  groups = full_name.gsub(base_name, "")
  return base_desc if groups.empty?
  groups = groups.gsub("_by_", "")
  desc = base_desc + " - grouped by "
  first = true
  GROUPS.each do |grp|
    info "Looking for group #{grp[0]} in #{groups}"
    if groups.include?(grp[0])
      desc += ", " unless first
      desc += grp[1].downcase
      first = false
      groups = groups.gsub(grp[0], "")
    end
  end

  unless groups.gsub("_", "").empty?
    error "Unable to parse table description for #{full_name} (remaining: #{groups})"
  end
  desc
end

def determine_simple_col_type(col_type)
  return "STRING" if col_type.include?("char") || col_type.include?("text")
  return "DATETIME" if col_type.include?("datetime") || col_type.include?("timestamp")
  return "INTEGER" if col_type.include?("int")
  return "FLOAT" if col_type.include?("float") || col_type.include?("double") || col_type.include?("decimal")
  return "DATE" if col_type.include?("date")
  error "Unknown column type #{col_type}"
end

def gen_yaml(table_name, table_cols, dtm_col, uid)
  data = {}
  data['table_name'] = table_name
  data['main_dttm_col'] = dtm_col
  data['description'] = determine_table_desc(table_name)
  data['default_endpoint'] = nil
  data['offset'] = 0
  data['cache_timeout'] = nil
  data['catalog'] = 'internal'
  data['schema'] = DATABASE
  data['sql'] = nil
  data['params'] = nil
  data['template_params'] = nil
  data['filter_select_enabled'] = true
  data['fetch_values_predicate'] = nil
  data['extra'] = nil
  data['normalize_columns'] = false
  data['always_filter_main_dttm'] = false
  data['folders'] = nil
  data['uuid'] = uid
  data['metrics'] = [
    {
      'metric_name' => 'count',
      'verbose_name' => 'COUNT(*)',
      'metric_type' => 'count',
      'expression' => 'COUNT(*)',
      'description' => nil,
      'd3format' => nil,
      'currency' => nil,
      'extra' => nil,
      'warning_text' => nil
    }
  ]
  cols = []
  table_cols.each do |col|
    cols << {
      'column_name' => col['Field'],
      'verbose_name' => nil,
      'is_dttm' => (col['Field'] == dtm_col),
      'is_active' => true,
      'type' => determine_simple_col_type(col['Type']),
      'advanced_data_type' => nil,
      'groupby' => (col['Field'] != dtm_col),
      'filterable' => (col['Field'] != dtm_col),
      'expression' => nil,
      'description' => col['Type'].include?("char") ? determine_col_desc(col['Field']) : nil,
      'python_date_format' => nil,
      'extra' => nil
    }
  end
  data['columns'] = cols
  data['version'] = '1.0.0'
  data['database_uuid'] = "c892601a-975c-4a61-98b3-94a6e6dad361"
  nil_to_null(data)
  File.write("#{table_name}.yaml" , data.deep_stringify_keys.to_yaml)
  # 'null' -> null
  text = File.read("#{table_name}.yaml")
  text.gsub!(/: 'null'/, ': null')
  File.write("#{table_name}.yaml" , text)
end

def nil_to_null(obj)
  if obj.is_a? Hash
    obj.each do |k, v|
      if v.nil?
        obj[k] = 'null'
      else
        nil_to_null(v)
      end
    end
  elsif obj.is_a? Array
    obj.each_with_index do |v, i|
      if v.nil?
        obj[i] = 'null'
      else
        nil_to_null(v)
      end
    end
  end
end

SQL_SESH.create_session(port: 9030) do |sesh|
  # pull table list
  sesh.query("SHOW TABLES FROM #{DATABASE}").each do |row|
    name = row.values[0]
    next if name.end_with?("_old")
    uid = SecureRandom.uuid
    if File.exist?("#{name}.yaml")
      uid = YAML.load_file("#{name}.yaml")['uuid']
    end
    table_cols = []
    sesh.query("SHOW COLUMNS FROM #{DATABASE}.#{name}").each do |col|
      table_cols << col
    end
    # find datetime column
    dtm_col = nil
    table_cols.each do |col|
      if col['Type'].downcase.start_with?('datetime') || col['Type'].downcase.start_with?('timestamp')
        dtm_col = col['Field']
        break
      end
    end
    gen_yaml(name, table_cols, dtm_col, uid)
  end
end
