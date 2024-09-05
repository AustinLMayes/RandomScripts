# Utilities for creating/updating Jira tasks

require_relative 'jira'

def bulk_create
    data = []
    File.open('/Users/austinmayes/Projects/Ruby/RandomScripts/jira_data.txt').each do |line|
        if line.start_with?("   ") || line.strip.empty?
            data[-1][:description] += line.strip.gsub("[]", "[link]") + "\n"
        else
            data << {parent: line.strip, children: [], description: ""}
        end
    end
    data.each do |issue|
        issue[:description] = Jira.to_adf(issue[:description])
    end
    # pp data
    Jira::Issues.create_multi(data, 'CC-7440', Jira::CC::BOARD_ID)
end

bulk_create
