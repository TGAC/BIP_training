require 'csv'
require 'json'
require 'uri'
require 'net/http'
require 'net/https'

# A sample Ruby client which:
#  1. Creates plant population submission.
#  2. Parses an input .csv file in search for Accessions, Lines, Varieties
#     and other input columns seen in # defining input columns from CSV.
#     For each line it the CSV it:
#    2a. Creates a Plant Variety (or finds in BIP, if it exists)
#    2b. Creates a Plant Line and links it with the Plant Variety.
#    2c. Creates a Plant Accession and links it with the Plant Line.
#  It submits data to BIP using the BIP API Key provided

if ARGV.size < 2
  STDERR.puts 'Not enough arguments. Usage:'
  STDERR.puts ' > ruby population_submission.rb input_file.csv api_key'
  exit 1
end

@client = Net::HTTP.new('bip.earlham.ac.uk', 443)
@client.use_ssl = true
@client.verify_mode = OpenSSL::SSL::VERIFY_NONE
@headers = {
  'Content-Type' => 'application/json',
  'X-BIP-Api-Key' => ARGV[1]
}

def pluralize_class(class_name)
  class_name == 'plant_variety' ? 'plant_varieties' : "#{class_name}s"
end

def test_error(response)
  unless response['reason'].nil?
    STDERR.puts "Encountered the following BIP request error."
    STDERR.puts response['reason']
    exit 1
  end
end

def call_bip(request)
  response = @client.request(request)
  JSON.parse(response.body).tap{ |parsed| test_error(parsed) }
end



# Attempts to create a resource record with data. Returns the created object id.
def create_record(class_name, data)
  request = Net::HTTP::Post.new("/api/v1/#{pluralize_class class_name}", @headers)
  request.body = { class_name => data }.to_json
  response = call_bip request
  if !response["errors"].nil? && response["errors"].size > 0
    STDERR.puts "Encountered the following error when creating #{class_name}."
    STDERR.puts response["errors"][0]["message"]
    exit 1
  end
  response[class_name]['id']
end


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#POPULATION SUBMISSION

puts " 1. Creating experimental plant_population "

plant_population_id = create_record('plant_population',
  name: 'workshop_test_pop', # for workshop: put a random number behind the population
  description: 'descr workshop_test_pop',
  establishing_organisation: 'EI',
  population_type_id: 3 , # Dh segregating:1 ,DFS:2 , DFFS: 3,F3 pooled:4 , Recombinant inbred: 5, F1 hybrid:6, Back Cross: 7
  taxonomy_term_id: 27  # Brassica napus id in BIP  27, Brassica oleracea: 32, Brassica rapa:1
)


#defining input columns from CSV
ACCESSION_NAME = 0
LINE_NAME = 3
VARIETY = 4
ACCESSION_SOURCE = 1
YEAR_PRODUCED = 2

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


# Function that finds or submits plant_varieties
def record_plant_variety(plant_variety_name)
  request = Net::HTTP::Get.new("/api/v1/plant_varieties?plant_variety[query][plant_variety_name]=#{URI.escape plant_variety_name}", @headers)
  response = call_bip request
  if response['meta']['total_count'] == 0
    create_record('plant_variety',
      plant_variety_name: plant_variety_name
    )
  else
    response['plant_varieties'][0]['id']
  end
end

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ALTERING THE RUBY CLIENT: FUNCTION PLANT LINE


# Function that finds or submits plant_lines
def record_plant_line(plant_line_name, plant_variety_id)   # workshop notes: add the genetic status here: ,genetic_status]
  request = Net::HTTP::Get.new("/api/v1/plant_lines?plant_line[query][plant_line_name]=#{URI.escape plant_line_name}", @headers)
  response = call_bip request
  if response['meta']['total_count'] == 0
    create_record('plant_line',
      plant_line_name: plant_line_name,
      plant_variety_id: plant_variety_id  #  <<-   workshop notes: add a comma here , so it looks like:  plant_variety_id: plant_variety_id,
      # genetic_status: genetic_status   #  remove the first '#' hashkey. This will add the submission of the genetic status object to the database.
    )
  else
    response['plant_lines'][0]['id']
  end
end


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


# Function that associates a plant line with a plant population through
# the so-called plant population lists
def associate_line_with_population(plant_line_id, plant_population_id)
  create_record('plant_population_list',
    plant_line_id: plant_line_id,
    plant_population_id: plant_population_id
  )
end


# Function that finds or submits plant_accessions
def record_plant_accession(plant_accession, originating_organisation, year_produced, plant_line_id)
  request = Net::HTTP::Get.new("/api/v1/plant_accessions?plant_accession[query][plant_accession]=#{plant_accession}", @headers)
  response = call_bip request
  if response['meta']['total_count'] == 0
    create_record('plant_accession',
      plant_accession: plant_accession,
      originating_organisation: originating_organisation,
      year_produced: year_produced,
      plant_line_id: plant_line_id
    )
  else
    response['plant_accessions'][0]['id']
  end
end


puts " 2. Parsing input CSV file and processing it line by line "

# Now, parse the input CSV file and record all important information
CSV.foreach(ARGV[0]) do |row|
  next if row[0]== 'Accession_name' # omit the header
  puts "  * processing Accession  #{row[ACCESSION_NAME]}"
  plant_variety_id = record_plant_variety(row[VARIETY])
  plant_line_id = record_plant_line(row[LINE_NAME], plant_variety_id)

  # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  associate_line_with_population(plant_line_id, plant_population_id) # workshop notes: add the genetic status here: ,row[GENETIC_STATUS]

  # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  record_plant_accession(row[ACCESSION_NAME], row[ACCESSION_SOURCE], row[YEAR_PRODUCED], plant_line_id)
end

puts '3. Finished'
