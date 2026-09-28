enum ActiveWindowMode { allDay, bounded }

final class ActiveWindow {
  ActiveWindow._({
    required this.mode,
    this.startMinute,
    this.endMinute,
  });

  factory ActiveWindow.allDay() {
    return ActiveWindow._(mode: ActiveWindowMode.allDay);
  }

  factory ActiveWindow.bounded({
    required int startMinute,
    required int endMinute,
  }) {
    if (startMinute < 0 || startMinute > 1439) {
      throw ArgumentError.value(
        startMinute,
        'startMinute',
        'startMinute must be between 0 and 1439',
      );
    }
    if (endMinute < 0 || endMinute > 1439) {
      throw ArgumentError.value(
        endMinute,
        'endMinute',
        'endMinute must be between 0 and 1439',
      );
    }
    if (startMinute == endMinute) {
      throw ArgumentError('Bounded active-window start and end must differ');
    }
    return ActiveWindow._(
      mode: ActiveWindowMode.bounded,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  final ActiveWindowMode mode;
  final int? startMinute;
  final int? endMinute;
}
