require 'versionable/models/version'

module Versionable
  module InstanceMethods
    def save(options={})
      save_version(options.delete(:updater_id)) if self.respond_to?(:rolling_back) && !rolling_back
      super
    end

    private
      def save_version(updater_id=nil)
        if self.respond_to?(:versions)
          version = self.current_version
          version.message = self.version_message
          if self.versions.empty?
            version.pos = 0
          else
            version.pos = self.versions.last.pos + 1
          end
          version.updater_id = updater_id
          version.save

          self.versions.shift if self.versions.count >= @limit
          self.versions << version

          @versions_count = @versions_count.to_i + 1
        end
      end
  end

  module ClassMethods
    def enable_versioning(opts={})
      attr_accessor :rolling_back

      key :version_number, Integer

      define_method(:version_message) do
        @version_message
      end

      define_method(:version_message=) do |message|
        @version_message = message
      end

      define_method(:versions_count) do
        @versions_count ||= Version.count(:doc_id => self._id.to_s)
      end

      define_method(:versions) do
        @limit ||= opts[:limit] || 10
        @versions ||= Version.all(:doc_id => self._id.to_s, :order => 'pos desc', :limit => @limit).reverse
      end

      define_method(:all_versions) do
        Version.where(:doc_id => self._id.to_s).sort(:pos.desc)
      end

      define_method(:rollback) do |pos = nil|
        #The last version is always same as the current version, so -2 instead of -1
        pos = self.versions.count-2 if pos.nil?
        version = self.version_at(pos)

        if version
          self.attributes = version.data
        end

        self.version_number = version.pos
        self
      end
      
      define_method(:rollback!) do |pos = nil|
        self.rollback(pos)

        @rolling_back = true
        save!
        @rolling_back = false

        self
      end

      define_method(:diff) do |key, pos1, pos2, format = :html|
        version1 = self.version_at(pos1)
        version2 = self.version_at(pos2)

        Differ.diff_by_word(version1.content(key), version2.content(key)).format_as(format)
      end

      define_method(:current_version) do
        Version.new(:data => self.attributes, :date => Time.now, :doc_id => self._id.to_s)
      end

      define_method(:version_at) do |pos|
        case pos
        when :current
          current_version
        when :first
          index = self.versions.index {|v| v.pos == 0}
          version = self.versions[index] if index
          version ||= Version.first(:user_id => self._id.to_s, :pos => 0)
          version
        when :last
          #The last version is always same as the current version, so -2 instead of -1
          self.versions[self.versions.count-2]
        when :latest
          self.versions.last
        else
          index = self.versions.index {|v| v.pos == pos}
          version = self.versions[index] if index
          version ||= Version.first(:user_id => self._id.to_s, :pos => pos)
          version 
        end
      end
    end
  end
end
