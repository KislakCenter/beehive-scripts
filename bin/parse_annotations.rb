#!/usr/bin/env ruby

require 'strscan'
require 'open-uri'
require 'set'
require 'jsonpath'
require 'csv'
require 'pp'

require 'htmlentities'
require 'rdf'
require 'sparql/client'

##
# Script to read and parse Bee Hive annotation linked data and convert it to
# CSV format. Output CSV data looks like the following.
#
#     volume,image_number,head,entry,topic,xref,index,item,unparsed,line,selection,full_image
#     Volume 1,455,,Execution,Execution,,execution,#item-a147ed4b8,,Entry: Execution|Topic: Execution|Index: execution|#item-a147ed4b8,"https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/347,288,3070,287/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/full/full/0/default.jpg
#     Volume 1,455,,Exercise,Exercise,1345 [Exercise],exercise,#item-d845c95d0,,Entry: Exercise|Topic: Exercise|XRef: 1345 [Exercise]|Index: exercise|#item-d845c95d0,"https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/373,602,3055,237/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/full/full/0/default.jpg
#     Volume 1,455,,Exorcism,Exorcism,Conjuration|1541 [Conjuring]|1551 [Gafers],exorcism,#item-a42a0b906,,Entry: Exorcism|Topic: Exorcism|XRef: Conjuration|XRef: 1541 [Conjuring]|XRef: 1551 [Gafers]|Index: exorcism|#item-a42a0b906,"https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/370,851,3093,235/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/full/full/0/default.jpg
#     Volume 1,455,,Experience,Experience,Skill|1345 [Experience],experience,#item-5d82b5199,,Entry: Experience|Topic: Experience|XRef: Skill|XRef: 1345 [Experience]|Index: experience|#item-5d82b5199,"https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/378,1093,3098,562/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/ps974xt6740%2F1607_0454/full/full/0/default.jpg
#     ...
#     Volume 2,285,,1406,adultery,,,#item-5c8343e31,,Entry: 1406|Topic: adultery|#item-5c8343e31,"https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0752/332,204,2931,519/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0752/full/full/0/default.jpg
#     Volume 2,285,,1408,Acceptable,,,#item-5ee82cb32,,Entry: 1408|Topic: Acceptable|#item-5ee82cb32,"https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0752/285,2096,3028,583/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0752/full/full/0/default.jpg
#     Volume 2,288,,1421,Atheism,1983,Atheism,#item-b2f1c1590,,Entry: 1421|Topic: Atheism|Index: Atheism|Xref: 1983|#item-b2f1c1590,"https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0755/864,254,2909,732/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/fm855tg5659%2F1607_0755/full/full/0/default.jpg
#     ...
#     Volume 3,47,term of life presint,4515 [PAGE_MISSING],,,,#item-fb43076d5,,Head: term of life presint|Entry: 4515 [PAGE_MISSING]|#item-fb43076d5,"https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/165,2473,732,89/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/full/full/0/default.jpg
#     Volume 3,47,terms,537 [WORD_ILLEGIBLE]|1364 [Casuists],,,,#item-621de2bf5,,Head: terms|Entry: 537 [WORD_ILLEGIBLE]|Entry: 1364 [Casuists]|#item-621de2bf5,"https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/162,2607,564,76/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/full/full/0/default.jpg
#     Volume 3,47,terra sigillata,1168 [Terra Sigillata],,,,#item-4b780e579,,Head: terra sigillata|Entry: 1168 [Terra Sigillata]|#item-4b780e579,"https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/152,2645,594,146/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/full/full/0/default.jpg
#     Volume 3,47,terrour,a|669 [Terrrour]&nbsp;,,,,#item-489021159,,Head: terrour|Entry: a|Entry: 669 [Terrrour]&nbsp;|#item-489021159,"https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/164,2777,483,141/full/0/default.jpg",https://stacks.stanford.edu/image/iiif/gw497tq8651%2F1607_0990/full/full/0/default.jpg
#     ...
#

##
# First we read the manifests to get the canvas, title, and image data.
#
manifests = %w{ https://purl.stanford.edu/ps974xt6740/iiif/manifest.json
  https://purl.stanford.edu/fm855tg5659/iiif/manifest.json
  https://purl.stanford.edu/gw497tq8651/iiif/manifest.json }

##
# Class to represent the book title, canvas and image URL,
# image number, value.
class CanvasData
  attr_accessor :title, :canvas_url, :image_url

  def initialize title, canvas_url, image_url
    @title        = title
    @canvas_url   = canvas_url
    @image_url    = image_url
  end

  def volume
    title.strip =~ /volume \d+$/i && $&
  end

  def image_number
    canvas_url.split(/_/).last
  end
end

CANVAS_DB  = {}
manifests.each do |manifest|
  json    = open(manifest).read
  # get the volume number from the title
  title   = JsonPath.on(json, 'metadata[?(@.label == "Title")].value').first

  # For each canvas get the URL of the canvas and the image, and the number of
  # image
  JsonPath.on(json, '$..canvases').first.each do |canvas|
    canvas_url = canvas['@id']
    image_url  = canvas['images'].first.dig('resource', '@id')
    CANVAS_DB[canvas_url] = CanvasData.new title, canvas_url, image_url
  end
end

##
# Find the struct of canvas data for the image for given canvas.
#
# @param [String] canvas_url
# @return [CanvasData] struct of canvas data
def find_canvas_data canvas_url
  CANVAS_DB[canvas_url]
end

HEADERS = %i{ volume image_number head entry topic page add xref see index item unparsed line selection full_image annotation_uri }

##
# Parse the content of an annotation
# @param [String] content object of annotation body's 'http://www.w3.org/2011/content#Chars'
# @return [Hash] parsed data
def parse_content content
  row = {}
  content = content.gsub('<br />', '|').gsub(/<\/?[^>]+>/, '').gsub(/\n/, '|').gsub('&nbsp;', ' ').strip
  content = HTMLEntities.new.decode content
  row[:line] = [content]
  if content =~ /Entry:|Head:/i
    content.split(/\|/).map(&:strip).each do |bit|
      parts = bit.split(/:\s+/, 2)
      case parts.first
      when /^Head/i
        (row[:head] ||= []) << parts.last
      when /^Entry/i
        (row[:entry] ||= []) << parts.last
      when /^Topic/i
        (row[:topic] ||= []) << parts.last
      when /^Page/i
        (row[:page] ||= []) << parts.last
      when /^Add/i
        (row[:add] ||= []) << parts.last
      when /^Xref/i
        (row[:xref]  ||= []) << parts.last
      when /^Index/
        (row[:index] ||= []) << parts.last
      when /^See$/i
        (row[:see] ||=[]) << parts.last
      when /^See\s/i
        # binding.pry if content =~ /brave/
        (row[:see] ||=[]) << parts.first.split(/\s+/, 2).last
      when /^#item/i
        (row[:item] ||= []) << parts.first
      else
        (row[:unparsed] ||= []) << parts.join(' ')
      end
    end
  else
    row[:unparsed] =  content.split(/\|/).map &:strip
  end

  row.each { |k,v| row[k] = (v || []).join '|' }
  row
end


# Query to select the annotation URL, annotation chars, canvas and image
# selector coordinates
content = RDF::Vocabulary.new 'http://www.w3.org/2011/content#'
oa      = RDF::Vocabulary.new 'http://www.w3.org/ns/oa#'
sparql  = SPARQL::Client.new('http://localhost:3030/beehive')
query = sparql.select(:annotation, :content, :canvas, :coordinates).
  where(
    [:annotation, RDF.type,       oa[:Annotation]],
    [:annotation, oa.hasBody,     :body],
    [:annotation, oa.hasTarget,   :target],
    [:body,       content.chars,  :content],
    [:target,     oa.hasSource,   :canvas],
    [:target,     oa.hasSelector, :selector],
    [:selector,   RDF.type,       oa[:FragmentSelector]],
    [:selector,   RDF.value,      :coordinates]
  )

##
# Print CSV to standard out
CSV headers: true do |csv|
  csv << HEADERS
  csv << { volume: 'Volume 0', image_number: 0, unparsed: 'Force Google Sheets to read CSV as UTF-8: büngt; if UTF-8 occurs too late, CSV will be read as ASCII' }
  query.each_solution do |solution|
    canvas_url            = solution[:canvas].value
    canvas_data           = find_canvas_data canvas_url

    row                   = parse_content solution[:content].value
    coordinates           = solution[:coordinates] && solution[:coordinates].value.split(/=/).last
    row[:volume]          = canvas_data.volume
    row[:image_number]    = canvas_data.image_number
    row[:selection]       = canvas_data.image_url.sub /full/, coordinates
    row[:full_image]      = canvas_data.image_url
    row[:annotation_uri]  = solution[:annotation].value
    csv << row
  end
end
