function clamp(v, min = 0, max = 1) {
  return Math.max(min, Math.min(max, v));
}

function evaluateBehavior(payload) {
  const amount = Number(payload.amount || 0);
  const knownReceiver = Boolean(payload.known_receiver);
  const txHour = Number(payload.tx_hour ?? new Date().getHours());
  const profile = payload.user_profile && typeof payload.user_profile === 'object'
    ? payload.user_profile
    : {};

  const txCountLast24h = Number(profile.tx_count_last_24h || 0);
  const deviceMismatch = Boolean(profile.device_mismatch);
  const locationMismatch = Boolean(profile.location_mismatch);

  let score = 0.05;
  const reasons = [];

  if (amount > 8000) {
    score += 0.25;
    reasons.push('Large payment compared to common range');
  }
  if (!knownReceiver) {
    score += 0.2;
    reasons.push('Unknown recipient');
  }
  if (txHour < 5 || txHour > 23) {
    score += 0.12;
    reasons.push('Unusual activity time');
  }
  if (txCountLast24h > 10) {
    score += 0.18;
    reasons.push('High transaction burst in 24h');
  }
  if (deviceMismatch || locationMismatch) {
    score += 0.2;
    reasons.push('Context mismatch (device/location)');
  }

  const anomalyScore = clamp(score);
  const isAnomaly = anomalyScore >= 0.65;

  return {
    anomaly_score: anomalyScore,
    is_anomaly: isAnomaly,
    reasons,
    action: isAnomaly ? 'trigger_verification' : 'allow',
  };
}

module.exports = {
  evaluateBehavior,
};
