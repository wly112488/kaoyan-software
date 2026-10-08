/// Calculates the maximum wait before content may re-enter the reminder queue.
///
/// The configured cooldown is a cap. A small active pool can complete a full
/// round sooner, while a larger pool naturally stretches the round according
/// to the global spacing between notifications.
Duration effectiveRepeatCooldown({
  required Duration maximumCooldown,
  required Duration globalInterval,
  required int activeContentCount,
}) {
  if (activeContentCount <= 0 || globalInterval <= Duration.zero) {
    return maximumCooldown;
  }

  final intervalMicros = globalInterval.inMicroseconds;
  final maximumMicros = maximumCooldown.inMicroseconds;
  if (activeContentCount > maximumMicros ~/ intervalMicros) {
    return maximumCooldown;
  }

  final roundDuration = Duration(
    microseconds: intervalMicros * activeContentCount,
  );
  return roundDuration < maximumCooldown ? roundDuration : maximumCooldown;
}
