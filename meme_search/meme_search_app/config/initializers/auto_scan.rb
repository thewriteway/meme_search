# Start auto-scan job on Rails boot
# Skip in test environment to avoid interference with tests
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless defined?(Rails::Server)

  # Wait 1 minute after server boot, then start the job.
  AutoScanImagePathsJob.set(wait: 1.minute).perform_later
  Rails.logger.info "[AutoScan] Job scheduled to start in 1 minute"
end
