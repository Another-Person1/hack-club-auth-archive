module YotiService
  class << self
    def instance
      @instance ||= if ENV["YOTI_SDK_ID"].present?
        YotiService::Production.new
      else
        YotiService::Mock.new
      end
    end

    def sdk_id
      ENV["YOTI_SDK_ID"] || raise("YOTI_SDK_ID not configured")
    end

    def key_file_path
      ENV["YOTI_KEY_FILE_PATH"] || raise("YOTI_KEY_FILE_PATH not configured")
    end
  end
end
