require 'yaml'

IN = ARGV[0]
raise "Please provide an input YAML file!" unless IN.is_a? String
raise "Input file #{IN} does not exist!" unless File.exists? IN

data = YAML.load_file(IN)

# glyph-widths
glyph_widths = data["glyph-widths"]
glyph_widths[9205] = 18
glyph_widths[9204] = 18
res = ""
data.each do |key, value|
  if value.is_a? Array
    res += "#{key}: [#{value.join(",")}]\n"
  else
    res += "#{key}: \"#{value}\"\n"
  end
end

OUT = ARGV[1] || IN
File.open(OUT, 'w') do |file|
  file.write res
end
