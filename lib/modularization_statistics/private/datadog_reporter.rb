# typed: strict
# frozen_string_literal: true

require 'dogapi'
require 'modularization_statistics/private/metrics'
require 'modularization_statistics/private/metrics/files'
require 'modularization_statistics/private/metrics/public_usage'
require 'modularization_statistics/private/metrics/protection_usage'
require 'modularization_statistics/private/metrics/rubocop_protections_exclusions'
require 'modularization_statistics/private/metrics/packages'
require 'modularization_statistics/private/metrics/packages_by_team'
require 'modularization_statistics/private/metrics/nested_packs'

module ModularizationStatistics
  module Private
    class DatadogReporter
      extend T::Sig

      sig do
        params(
          source_code_files: T::Array[SourceCodeFile],
          app_name: String
        ).returns(T::Array[GaugeMetric])
      end
      def self.get_metrics(source_code_files:, app_name:)
        packages = ParsePackwerk.all

        [
          *Metrics::Files.get_metrics(source_code_files, app_name),
          *Metrics::Packages.get_package_metrics(packages, app_name),
          *Metrics::PackagesByTeam.get_package_metrics_by_team(packages, app_name),
          *Metrics::NestedPacks.get_nested_package_metrics(packages, app_name)
        ]
      end

      sig do
        params(
          datadog_client: Dogapi::Client,
          # Since `gauge` buckets data points we need to use the same time for all API calls
          # to ensure they fall into the same bucket.
          report_time: Time,
          metrics: T::Array[GaugeMetric]
        ).void
      end
      def self.report!(datadog_client:, report_time:, metrics:)
        #
        # Batching the metrics sends a post request to DD
        # we want to split this up into chunks of 1000 so that as we add more metrics,
        # our payload is not rejected for being too large
        #
        metrics.each_slice(1000).each do |metric_slice|
          datadog_client.batch_metrics do
            metric_slice.each do |metric|
              datadog_client.emit_points(metric.name, [[report_time, metric.count]], type: 'gauge', tags: metric.tags.map(&:to_s))
            end
          end
        end
      end
    end
  end
end
