require 'net/http'
require 'uri'
require 'yajl'

class ApiData
  attr_accessor :refs, :bookmarks, :types, :tags, :forms
end

class Api
  attr_accessor :refs, :bookmarks, :forms, :master

  def initialize(data)
    @bookmarks = data['bookmarks']
    @refs = get_refs_from_data(data)
    @forms = get_forms_from_data(data)
    @master = get_master_from_data
  end

  def self.get(url, path = '/api')
    http = Net::HTTP.new(URI(url).host)
    req = Net::HTTP::Get.new(path, { 'Accept' => 'application/json' })
    res = http.request(req)

    if res.code == '200'
      res
    else
      raise PrismicWSConnectionError, res.message
    end
  end

  def self.parse_api_response(data)
    parser = Yajl::Parser.new
    hash = parser.parse(data)

    create_refs = lambda do
      hash['refs'].map do |ref|
        Ref.new(ref['ref'], ref['label'], ref['isMasterRef'])
      end
    end

    create_forms = lambda do
      Hash[
        hash['forms'].map do |k, form|
          create_form_fields = lambda do
            Hash[form['fields'].map { |k2, field|
              [k2, Field.new(field['type'], field['default'])]
            }]
          end

          [k, Form.new(
            form['name'],
            create_form_fields.call,
            form['method'],
            form['rel'],
            form['enctype'],
            form['action'],
          )]
        end
      ]
    end

    {
      'bookmarks' => hash['bookmarks'],
      'forms'     => create_forms.call,
      'refs'      => create_refs.call,
      'tags'      => hash['tags'],
      'types'     => hash['types']
    }
  end

  private

  def get_refs_from_data(data)
    Hash[data['refs'].map { |ref| [ref.label, ref] }]
  end

  def get_forms_from_data(data)
    data['forms'] = data['forms'] || {}
    Hash[data['forms'].map { |key, form|
      [key, SearchForm.new(self, form, form.default_data)]
    }]
  end

  def get_master_from_data
    master = @refs.values.map { |ref| ref if ref.master? }.compact.first

      if not master.nil?
        master
      else
        raise NoMasterFoundException
      end
  end

  class NoMasterFoundException < Exception
  end

  class PrismicWSConnectionError < Exception
    def initialize(msg)
      super("Can't connect to Prismic's API: #{msg}")
    end
  end
end

class Form
  attr_accessor :name, :form_method, :rel, :enctype, :action, :fields

  def initialize(name, fields, form_method, rel, enctype, action)
    @name = name
    @fields = fields
    @form_method = form_method
    @rel = rel
    @enctype = enctype
    @action = action
  end

  def default_data
    fields.select do |k, v|
      not v.nil?
    end
  end
end

class SearchForm
  attr_accessor :api, :form, :data

  def initialize(api, form, data)
    @api = api
    @form = form
    @data = data
  end
end

class Field
  attr_accessor :field_type, :default

  def initialize(field_type, default)
    @field_type = field_type
    @default = default
  end
end

class Document
  attr_accessor :id, :type, :href, :tags, :slugs, :fragments
end

class Ref
  attr_accessor :ref, :label, :master, :scheduledAt

  def initialize(ref, label, master = false)
    @ref = ref
    @label = label
    @master = master
  end

  alias :master? :master
end
