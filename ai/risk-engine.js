function clamp(v, min = 0, max = 1) {
  return Math.max(min, Math.min(max, v));
}

function average(values) {
  if (!Array.isArray(values) || values.length === 0) return 0;
  const valid = values.map(Number).filter((v) => Number.isFinite(v) && v > 0);
  if (valid.length === 0) return 0;
  return valid.reduce((a, b) => a + b, 0) / valid.length;
}

function classifyRisk(score) {
  if (score >= 0.75) return 'High Risk';
  if (score >= 0.4) return 'Medium Risk';
  return 'Safe';
}

function evaluateTransactionRisk(payload) {
  const amount = Number(payload.amount || 0);
  const knownReceiver = Boolean(payload.known_receiver);
  const txCountLast24h = Number(payload.tx_count_last_24h || 0);
  const deviceMismatch = Boolean(payload.device_mismatch);
  const locationMismatch = Boolean(payload.location_mismatch);
  const unusualSpending = Boolean(payload.unusual_spending_pattern);
  const historical = Array.isArray(payload.historical_amounts) ? payload.historical_amounts : [];

  let score = 0.08;
  const triggers = [];

  if (amount > 5000) {
    score += 0.2;
    triggers.push('High transaction amount');
  }
  if (!knownReceiver) {
    score += 0.22;
    triggers.push('Receiver not in known contacts');
  }
  if (txCountLast24h > 8) {
    score += 0.18;
    triggers.push('Unusual transaction frequency');
  }
  if (deviceMismatch || locationMismatch) {
    score += 0.2;
    triggers.push('Device or location mismatch');
  }
  if (unusualSpending) {
    score += 0.15;
    triggers.push('Unusual spending pattern');
  }

  const avgHistory = average(historical);
  if (avgHistory > 0 && amount > avgHistory * 3) {
    score += 0.15;
    triggers.push('Amount is far above historical average');
  }

  const riskScore = clamp(score);
  const classification = classifyRisk(riskScore);

  return {
    risk_score: riskScore,
    classification,
    triggers,
    require_extra_verification: classification === 'High Risk',
    delay_recommended: classification === 'High Risk' && amount > 7000,
  };
}

module.exports = {
  evaluateTransactionRisk,
  classifyRisk,
};
