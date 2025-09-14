# frozen_string_literal: true

# name: discourse-media-watermark
# about: Synchronous watermarking for image and video uploads (works with S3 FileStore)
# version: 1.0.0
# authors: SJ

gem "mini_magick", "4.12.0", require: false

# toggle to enable/disable entire plugin from site settings (optional)
enabled_site_setting :media_watermark_enabled

after_initialize do
  require "shellwords"
  require "tempfile"
  require "open3"

  module ::DiscourseMediaWatermark
    PLUGIN_NAME = "discourse-media-watermark"
    WATERMARK_ASSET = Rails.root.join("plugins", "discourse-media-watermark", "assets", "images", "watermark.png")
    LOG_PREFIX = "[media_watermark]"

    # ---- Config guards (safe checks) ----
    def self.ffmpeg_available?
      @ffmpeg_available ||= system("which ffmpeg > /dev/null 2>&1")
    end

    def self.minimagick_available?
      @minimagick_available ||= begin
        require "mini_magick"
        true
      rescue LoadError
        false
      end
    end

    def self.watermark_exists?
      File.exist?(WATERMARK_ASSET)
    end

    # OPTIONAL SIZE GUARD (in bytes). Return true if file size <= threshold or threshold nil.
    # Default is 10 MB here (as you had), change if desired.
    def self.size_ok?(path, threshold_bytes = 10 * 1024 * 1024)
      return false unless path && File.exist?(path)
      return true if threshold_bytes.nil?
      File.size(path) <= threshold_bytes
    end

    # -------------------- IMAGE PROCESSING --------------------
    # Returns an ActionDispatch::Http::UploadedFile or nil on skip/failure
    def self.process_image_upload(uploaded)
      return nil unless minimagick_available?
      return nil unless watermark_exists?

      begin
        # Determine source path (best-effort)
        src_path = if uploaded.respond_to?(:tempfile) && uploaded.tempfile.respond_to?(:path)
                     uploaded.tempfile.path
                   elsif uploaded.respond_to?(:path) && File.exist?(uploaded.path)
                     uploaded.path
                   else
                     tmp_src = Tempfile.new(['dmw_image_src', File.extname(uploaded.original_filename.to_s)])
                     tmp_src.binmode
                     tmp_src.write(uploaded.read)
                     tmp_src.flush
                     tmp_src.path
                   end

        return nil unless src_path && File.exist?(src_path)
        return nil unless size_ok?(src_path)

        require "mini_magick"
        img = MiniMagick::Image.open(src_path)
        watermark = MiniMagick::Image.open(WATERMARK_ASSET)   # <-- fixed: open watermark asset, not src_path

        # scale watermark to a percent of image width
        scale_percent = 10
        target_w = (img.width * scale_percent / 100.0).round
        watermark.resize("#{target_w}x")

        padding = 20

        result = img.composite(watermark) do |c|
          c.gravity "SouthWest"
          c.geometry "+#{padding}+#{padding}"
        end

        tmp_out = Tempfile.new(['watermarked', File.extname(uploaded.original_filename.to_s)])
        tmp_out.binmode
        result.write(tmp_out.path)
        tmp_out.rewind

        ActionDispatch::Http::UploadedFile.new(
          filename: uploaded.original_filename || File.basename(tmp_out.path),
          type: (uploaded.content_type || "image/png"),
          tempfile: tmp_out
        )
      rescue => e
        Rails.logger.error("#{LOG_PREFIX} image processing failed: #{e.class} #{e.message}\n#{e.backtrace.take(10).join("\n")}")
        nil
      end
    end

    # -------------------- VIDEO PROCESSING --------------------
    # Returns an ActionDispatch::Http::UploadedFile or nil on skip/failure
    def self.process_video_upload(uploaded)
      return nil unless ffmpeg_available?
      return nil unless watermark_exists?

      # Determine source path
      src_path = if uploaded.respond_to?(:tempfile) && uploaded.tempfile.respond_to?(:path)
                   uploaded.tempfile.path
                 elsif uploaded.respond_to?(:path) && File.exist?(uploaded.path)
                   uploaded.path
                 else
                   tmp_src = Tempfile.new(['dmw_video_src', File.extname(uploaded.original_filename.to_s)])
                   tmp_src.binmode
                   tmp_src.write(uploaded.read)
                   tmp_src.flush
                   tmp_src.path
                 end

      return nil unless src_path && File.exist?(src_path)
      return nil unless size_ok?(src_path)

      begin
        out = Tempfile.new(['video_watermarked', '.mp4'])
        out_path = out.path
        out.binmode
        # out.close
        # keep out open/available for ffmpeg to write to path; close the Ruby handle now (we'll reopen later)
        out.close

        # scale watermark to 15% of video width, overlay 10px from left and bottom
        # tweak the 0.15 value to make watermark smaller/larger (0.10 = 10%, 0.20 = 20%, etc.)
        filter_complex = "[1][0]scale2ref=w=iw*0.10:h=ow/mdar[wm][vid];[vid][wm]overlay=10:main_h-overlay_h-10[outv]"

        cmd = [
          "ffmpeg",
          "-y",
          "-hide_banner",
          "-loglevel", "error",
          "-i", Shellwords.escape(src_path),                 # input 0 = video
          "-i", Shellwords.escape(WATERMARK_ASSET.to_s),     # input 1 = watermark
          "-filter_complex", Shellwords.escape(filter_complex),
          "-map", "\"[outv]\"",                              # map the processed video stream (note: we quote label)
          "-map", "0:a?",                                    # map audio if present
          "-c:v", "libx264",
          "-preset", "veryfast",
          "-crf", "23",
          "-c:a", "copy",
          Shellwords.escape(out_path)
        ].join(" ")

        # overlay_expr = "overlay=20:main_h-overlay_h-20"

        # cmd = [
        #   "ffmpeg",
        #   "-y",
        #   "-hide_banner",
        #   "-loglevel", "error",
        #   "-i", Shellwords.escape(src_path),
        #   "-i", Shellwords.escape(WATERMARK_ASSET.to_s),
        #   "-filter_complex", Shellwords.escape(overlay_expr),
        #   "-map", "0:v",
        #   "-map", "0:a?",
        #   "-c:v", "libx264",
        #   "-preset", "veryfast",
        #   "-crf", "23",
        #   "-c:a", "copy",
        #   Shellwords.escape(out_path)
        # ].join(" ")

        Rails.logger.info("#{LOG_PREFIX} running ffmpeg on #{src_path}")
        # success = system(cmd)
        
        stdout_s, stderr_s, status = Open3.capture3(cmd)

        unless status.success? && File.exist?(out_path) && File.size(out_path) > 0
          Rails.logger.error("#{LOG_PREFIX} ffmpeg failed or produced empty output.")
          # return nil
          
          # Cleanup out file
          begin
            File.delete(out_path) if File.exist?(out_path)
          rescue => _; end
          return nil
        end

        # copy ffmpeg output into a Tempfile instance that will be given to Rails
        wrapper = Tempfile.new(['dmw_upload', '.mp4'])
        wrapper.binmode
        File.open(out_path, "rb") do |f|
          # copy in chunks to avoid loading entire file into memory
          while (chunk = f.read(16 * 1024))
            wrapper.write(chunk)
          end
        end
        wrapper.flush
        wrapper.rewind

        # cleanup the ffmpeg output file on disk (we copied contents)
        begin
          File.delete(out_path) if File.exist?(out_path)
        rescue => _; end    
        
        # processed_tempfile = File.open(out_path, "rb")
        ActionDispatch::Http::UploadedFile.new(
          # tempfile: processed_tempfile,
          # filename: "video_watermarked_#{Time.now.to_i}.mp4",
          # type: "video/mp4"
          
          tempfile: wrapper,
          filename: uploaded.original_filename.present? ? "watermarked_#{uploaded.original_filename}" : "video_watermarked_#{Time.now.to_i}.mp4",
          type: (uploaded.content_type || "video/mp4")
        )
      rescue => e
        Rails.logger.error("#{LOG_PREFIX} video processing failed: #{e.class} #{e.message}\n#{e.backtrace.take(10).join("\n")}")
        nil
      end
    end
  end

  # == Controller patch: single interception ==
  require_dependency "uploads_controller"

  module ::DiscourseMediaWatermark
    module UploadsControllerPatch
      def self.prepended(base)
        base.prepend_before_action :apply_media_watermark_to_uploaded_file, only: [:create]
      end

      private

      def apply_media_watermark_to_uploaded_file
        begin
          # Respect the global toggle (enabled_site_setting :media_watermark_enabled)
          if defined?(SiteSetting) && SiteSetting.respond_to?(:media_watermark_enabled) && !SiteSetting.media_watermark_enabled
            Rails.logger.debug("#{DiscourseMediaWatermark::LOG_PREFIX} plugin globally disabled via SiteSetting.media_watermark_enabled")
            return
          end

          incoming = params[:file] || params[:upload] || params[:qqfile] || params[:attachment]
          return if incoming.blank?

          # Determine content type robustly
          content_type = nil
          content_type = incoming.content_type.to_s if incoming.respond_to?(:content_type) && incoming.content_type
          content_type ||= (incoming.respond_to?(:headers) && incoming.headers && incoming.headers['Content-Type'])
          content_type ||= (incoming.respond_to?(:[]) && (incoming['Content-Type'] || incoming[:content_type])) rescue nil

          # fallback by extension
          if content_type.blank? && incoming.respond_to?(:original_filename)
            ext = File.extname(incoming.original_filename || '').downcase
            content_type = case ext
                           when ".mp4" then "video/mp4"
                           when ".mov" then "video/quicktime"
                           when ".webm" then "video/webm"
                           when ".jpg", ".jpeg" then "image/jpeg"
                           when ".png" then "image/png"
                           else nil
                           end
          end

          return if content_type.blank?

          # Per-type toggles (optional SiteSettings if you add them later)
          image_enabled = if defined?(SiteSetting) && SiteSetting.respond_to?(:media_watermark_image_enabled)
                            SiteSetting.media_watermark_image_enabled
                          else
                            true
                          end
          video_enabled = if defined?(SiteSetting) && SiteSetting.respond_to?(:media_watermark_video_enabled)
                            SiteSetting.media_watermark_video_enabled
                          else
                            true
                          end

          if content_type.start_with?("image") && image_enabled
            processed = DiscourseMediaWatermark.process_image_upload(incoming)

            if processed && processed.respond_to?(:tempfile)
              params[:file] = processed
              params.delete(:qqfile)
              params.delete(:upload)
              Rails.logger.info("#{DiscourseMediaWatermark::LOG_PREFIX} replaced image upload with watermarked version")
            else
              Rails.logger.debug("#{DiscourseMediaWatermark::LOG_PREFIX} image processor skipped or failed")
            end

          elsif content_type.start_with?("video") && video_enabled
            filename = incoming.respond_to?(:original_filename) ? incoming.original_filename.to_s : (incoming.respond_to?(:path) ? File.basename(incoming.path) : nil)
            if filename && filename.include?("video_watermarked")
              Rails.logger.debug("#{DiscourseMediaWatermark::LOG_PREFIX} detected already-processed video; skipping")
              return
            end

            processed = DiscourseMediaWatermark.process_video_upload(incoming)
            if processed && processed.respond_to?(:tempfile)
              params[:file] = processed
              params.delete(:qqfile)
              params.delete(:upload)
              Rails.logger.info("#{DiscourseMediaWatermark::LOG_PREFIX} replaced video upload with watermarked version")
            else
              Rails.logger.debug("#{DiscourseMediaWatermark::LOG_PREFIX} video processor skipped or failed")
            end
          else
            Rails.logger.debug("#{DiscourseMediaWatermark::LOG_PREFIX} not image/video or disabled: #{content_type}")
          end
        rescue => e
          Rails.logger.error("#{DiscourseMediaWatermark::LOG_PREFIX} unexpected error in before_action: #{e.class} #{e.message}\n#{e.backtrace.take(10).join("\n")}")
          # let upload proceed
        end
      end
    end
  end

  if UploadsController.ancestors.exclude?(DiscourseMediaWatermark::UploadsControllerPatch)
    UploadsController.prepend DiscourseMediaWatermark::UploadsControllerPatch
  end
end
