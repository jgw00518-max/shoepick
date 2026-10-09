import 'package:shoepick_staff_app/model/staff_views.dart';

class OverviewMetric {
  const OverviewMetric(this.label, this.value, this.caption);

  final String label;
  final String value;
  final String caption;
}

class OverviewAlert {
  const OverviewAlert(this.title, this.description, this.view);

  final String title;
  final String description;
  final StaffView view;
}

class OverviewSnapshot {
  const OverviewSnapshot(this.metrics, this.alerts, {this.warnings = const []});

  final List<OverviewMetric> metrics;
  final List<OverviewAlert> alerts;
  final List<String> warnings;
}
