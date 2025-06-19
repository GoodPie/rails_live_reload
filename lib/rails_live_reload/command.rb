module RailsLiveReload
  class Command
    attr_reader :dt, :files

    def initialize(params)
      @dt    = params["dt"].to_i
      @files = JSON.parse(params["files"]) rescue []
    end

    def changes
      RailsLiveReload::Checker.scan(dt, files)
    end

    def reload?
      !changes.size.zero?
    end

    def css_only_changes?
      return false unless reload?
      changes.all? { |file| css_file?(file) }
    end

    def css_file?(file)
      file.match?(/\.css(\.|$)/)
    end

    def payload
      if reload?
        if css_only_changes?
          { command: "CSS_RELOAD" }
        else
          { command: "RELOAD" }
        end
      else
        { command: "NO_CHANGES" }
      end
    end

  end
end
