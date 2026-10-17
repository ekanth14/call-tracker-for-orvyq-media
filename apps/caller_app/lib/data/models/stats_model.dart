class StatsModel {
  final int totalCallsToday;
  final int connectedCallsToday;
  final int interestedToday;
  final int pendingCallbacksToday;

  StatsModel({
    this.totalCallsToday = 0,
    this.connectedCallsToday = 0,
    this.interestedToday = 0,
    this.pendingCallbacksToday = 0,
  });

  double get connectionRate {
    if (totalCallsToday == 0) return 0.0;
    return (connectedCallsToday / totalCallsToday) * 100;
  }
}
