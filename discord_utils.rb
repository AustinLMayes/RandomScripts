# Utilities for generating Ziax Changelogs

require 'common'

class ChangeLogBuilder
    def initialize
        @result = ""
    end

    def add(text, scope, platform)
        scope = scope_name(scope)
        platform = platform_name(platform)
        platform = " (#{platform})" if platform != ""
        @result += Discord::Markdown.bold(scope) + " - #{text} #{platform}\n"
    end

    def render
        result = @result
        result += Discord::CcMentions::Roles.changelog
        result
    end

    private

    def scope_name(scope)
        case scope
        when :global
            "Global"
        when :lobby
            "Lobby"
        when :li
            "Lucky Islands"
        when :sw
            "SkyWars"
        when :bew
            "BedWars"
        when :blw
            "BlockWars"
        when :ew
            "EggWars"
        when :ffa
            "FFA"
        when :mw
            "MinerWare"
        when :park
            "Parkour"
        when :pof
            "Pillars of Fortune"
        when :sb
            "SkyBlock"
        when :sg
            "Survival Games"
        else
            raise "Unknown scope: #{scope}"
        end
    end

    def platform_name(platform)
        case platform
        when :none
            ""
        when :java
            "Java"
        when :bedrock
            "Bedrock"
        when :both
            "Bedrock/Java"
        else
            raise "Unknown platform: #{platform}"
        end
    end
end

def gen_changelog
    builder = ChangeLogBuilder.new
    builder.add("Made chat filter less strict in parties/on signs", :global, :both)
    Clipboard.copy(builder.render)
end

gen_changelog
