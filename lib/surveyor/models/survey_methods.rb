require 'surveyor/common'
require 'rabl'

module Surveyor
  module Models
    module SurveyMethods
      def self.included(base)
        # Associations
        base.send :has_many, :sections, :class_name => "SurveySection", :order => "#{SurveySection.quoted_table_name}.display_order", :dependent => :destroy
        base.send :has_many, :sections_with_questions, :include => :questions, :class_name => "SurveySection", :order => "#{SurveySection.quoted_table_name}.display_order"
        base.send :has_many, :response_sets
        base.send :has_many, :translations, :class_name => "SurveyTranslation"

        # Scopes
        base.send :scope, :with_sections, {:include => :sections}

        @@validations_already_included ||= nil
        unless @@validations_already_included
          # Validations
          base.send :validates_presence_of, :title
          base.send :validates_uniqueness_of, :survey_version, :scope => :access_code, :message => "survey with matching access code and version already exists"

          @@validations_already_included = true
        end

        # Whitelisting attributes
        base.send :attr_accessible, :title, :description, :reference_identifier, :data_export_identifier, :common_namespace, :common_identifier, :css_url, :custom_class, :display_order

        # Derived attributes
        base.send :before_save, :generate_access_code
        base.send :before_save, :increment_version

        # Class methods
        base.instance_eval do
          def to_normalized_string(value)
            # replace non-alphanumeric with "-". remove repeat "-"s. don't start or end with "-"
            value.to_s.downcase.gsub(/[^a-z0-9]/,"-").gsub(/-+/,"-").gsub(/-$|^-/,"")
          end
        end
      end

      # Instance methods
      def initialize(*args)
        super(*args)
        default_args
      end

      def default_args
        self.api_id ||= Surveyor::Common.generate_api_id
        self.display_order ||= Survey.count
      end

      def active?
        self.active_as_of?(DateTime.now)
      end
      def active_as_of?(date)
        (active_at && active_at < date && (!inactive_at || inactive_at > date)) ? true : false
      end
      def activate!
        self.active_at = DateTime.now
        self.inactive_at = nil
      end
      def deactivate!
        self.inactive_at = DateTime.now
        self.active_at = nil
      end

      def as_json(options = nil)
        template_paths = ActionController::Base.view_paths.collect(&:to_path)
        Rabl.render(filtered_for_json, 'surveyor/export.json', :view_path => template_paths, :format => "hash")
      end

      ##
      # A hook that allows the survey object to be modified before it is
      # serialized by the #as_json method.
      def filtered_for_json
        self
      end

      def default_access_code
        self.class.to_normalized_string(title)
      end

      def generate_access_code
        self.access_code ||= default_access_code
      end

      def increment_version
        surveys = self.class.select(:survey_version).where(:access_code => access_code).order("survey_version DESC")
        next_version = surveys.any? ? surveys.first.survey_version.to_i + 1 : 0

        self.survey_version = next_version
      end

      def translation(locale_symbol)
        t = self.translations.where(:locale => locale_symbol.to_s).first
        {:title => self.title, :description => self.description}.with_indifferent_access.merge(
          t ? YAML.load(t.translation || "{}").with_indifferent_access : {}
        )
      end
    end
  end
end
